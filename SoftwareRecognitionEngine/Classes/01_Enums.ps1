enum MatchMethod {
    None     = 0
    Exact    = 1
    Rule     = 2
    Fuzzy    = 3
    Learned  = 4
}

enum RuleAction {
    SetFamily  = 0
    SetVendor  = 1
    StripToken = 2
    Replace    = 3
    Exclude    = 4
}
