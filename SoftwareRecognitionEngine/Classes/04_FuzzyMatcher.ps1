class FuzzyMatchResult {
    [string] $CandidateKey
    [int]    $FamilyId
    [int]    $ProductId
    [string] $FamilyName
    [int]    $Confidence    # 0-100
    [string] $Method        # 'Levenshtein', 'Jaccard', 'Hybrid'
}

class FuzzyMatcher {
    [int]   $MinConfidence        = 60   # below this score, no match is returned
    [int]   $LevenshteinThreshold = 3    # max edit distance before Levenshtein score floors to 0
    [float] $LevenshteinWeight    = 0.6
    [float] $JaccardWeight        = 0.4

    # Pure PowerShell Levenshtein using a 1-D rolling array (O(min(m,n)) space)
    [int] LevenshteinDistance([string]$a, [string]$b) {
        $la = $a.Length
        $lb = $b.Length
        if ($la -eq 0) { return $lb }
        if ($lb -eq 0) { return $la }

        # Ensure a is the shorter string to minimise memory
        if ($la -gt $lb) {
            $tmp = $a; $a = $b; $b = $tmp
            $tmp = $la; $la = $lb; $lb = $tmp
        }

        $prev = [int[]]::new($la + 1)
        $curr = [int[]]::new($la + 1)
        for ($i = 0; $i -le $la; $i++) { $prev[$i] = $i }

        for ($j = 1; $j -le $lb; $j++) {
            $curr[0] = $j
            for ($i = 1; $i -le $la; $i++) {
                $cost = if ($a[$i - 1] -ceq $b[$j - 1]) { 0 } else { 1 }
                $curr[$i] = [Math]::Min(
                    [Math]::Min($prev[$i] + 1, $curr[$i - 1] + 1),
                    $prev[$i - 1] + $cost
                )
            }
            $tmp  = $prev
            $prev = $curr
            $curr = $tmp
        }
        return $prev[$la]
    }

    # Jaccard similarity on word-token sets (case-insensitive)
    [float] JaccardSimilarity([string]$a, [string]$b) {
        $tokensA = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]($a.ToLower() -split '[\s\-_/\\]+' | Where-Object { $_ }),
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $tokensB = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]($b.ToLower() -split '[\s\-_/\\]+' | Where-Object { $_ }),
            [System.StringComparer]::OrdinalIgnoreCase
        )

        if ($tokensA.Count -eq 0 -and $tokensB.Count -eq 0) { return 1.0 }
        if ($tokensA.Count -eq 0 -or  $tokensB.Count -eq 0) { return 0.0 }

        $intersection = [System.Collections.Generic.HashSet[string]]::new($tokensA, [System.StringComparer]::OrdinalIgnoreCase)
        $intersection.IntersectWith($tokensB)

        $union = [System.Collections.Generic.HashSet[string]]::new($tokensA, [System.StringComparer]::OrdinalIgnoreCase)
        $union.UnionWith($tokensB)

        return [float]$intersection.Count / [float]$union.Count
    }

    # Combined confidence score 0-100 (Levenshtein + Jaccard weighted average)
    [int] Score([string]$query, [string]$candidate) {
        $q = $query.ToLower().Trim()
        $c = $candidate.ToLower().Trim()

        if ($q -eq $c) { return 100 }

        $maxLen = [Math]::Max($q.Length, $c.Length)
        if ($maxLen -eq 0) { return 0 }

        $lev      = $this.LevenshteinDistance($q, $c)
        $levScore = [Math]::Max(0.0, 100.0 - ([float]$lev / [float]$maxLen * 100.0))
        $jacScore = $this.JaccardSimilarity($q, $c) * 100.0

        $combined = ($levScore * $this.LevenshteinWeight) + ($jacScore * $this.JaccardWeight)
        return [int][Math]::Round($combined)
    }

    # Tokenize a normalized product name into searchable index tokens.
    # Tokens under 3 chars and common stop-words are excluded.
    [string[]] Tokenize([string]$name) {
        $stopWords = @('the','for','and','with','from','via','by','of','in','on','at','to','a','an')
        $tokens = $name.ToLower() -split '[\s\-_/\\\.()]+'
        return $tokens |
            Where-Object { $_.Length -ge 3 -and $_ -notin $stopWords } |
            Select-Object -Unique
    }

    # Given a query string and a list of candidate strings, return the best FuzzyMatchResult.
    # candidates is a hashtable: normalizedName -> @{FamilyId, ProductId, FamilyName}
    [FuzzyMatchResult] FindBest([string]$query, [hashtable]$candidates) {
        $best = $null

        foreach ($key in $candidates.Keys) {
            $score = $this.Score($query, $key)
            if ($score -ge $this.MinConfidence) {
                if ($null -eq $best -or $score -gt $best.Confidence) {
                    $meta   = $candidates[$key]
                    $best   = [FuzzyMatchResult]@{
                        CandidateKey = $key
                        FamilyId     = $meta.FamilyId
                        ProductId    = $meta.ProductId
                        FamilyName   = $meta.FamilyName
                        Confidence   = $score
                        Method       = 'Hybrid'
                    }
                }
            }
        }

        return $best  # $null if no candidate met MinConfidence
    }
}
