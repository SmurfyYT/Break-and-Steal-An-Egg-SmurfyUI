-- Prometheus settings for the published (obfuscated) build of SmurfysUI.lua.
-- Based on Prometheus' "Medium" preset, minus:
--   * AntiTamper: can falsely trigger in some executors.
--   * Vmify: on a script this big it randomly miscompiles code (depends on
--     the random seed), e.g. fly broke in one build. 20/20 test builds
--     without it work; with it about 1 in 8 is broken somewhere.
-- build.sh runs build/test on every build to catch broken output.
return {
    LuaVersion = "LuaU",
    VarNamePrefix = "",
    NameGenerator = "MangledShuffled",
    PrettyPrint = false,
    Seed = 0,
    Steps = {
        { Name = "EncryptStrings", Settings = {} },
        {
            Name = "ConstantArray",
            Settings = {
                Threshold = 1,
                StringsOnly = true,
                Shuffle = true,
                Rotate = true,
                LocalWrapperThreshold = 0,
            },
        },
        { Name = "NumbersToExpressions", Settings = {} },
        { Name = "WrapInFunction", Settings = {} },
    },
}
