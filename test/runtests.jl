using DataFrameGates
using DataFrames
using Intervals
using Test
using Unitful
@testset "Basic gates" begin
    df = DataFrame(
        x = [1, 2, 3, 4, 5],
        y = [1.1, 2.2, 3.3, 4.4, 5.5]
    )

    gate = AlwaysGate()
    filtered = filter(gate, df)
    @test filtered == df

    gate = SelectionGate(:x, 3)  
    filtered = remove_cache_columns(filter(gate, df))
    @test size(filtered) == (1, 2)
    @test only(filtered.y) == 3.3
    @test gate == SelectionGate(:x, 3)  # Make sure that equality holds for separate instances

    gate = MemberGate(:y, [2.2, 5.5])
    filtered = remove_cache_columns(filter(gate, df))
    @test size(filtered) == (2, 2)
    @test filtered.x == [2, 5]
    @test gate == MemberGate(:y, [2.2, 5.5])  # Make sure that equality holds for separate instances

    gate = MemberGate(:x, 1..3.1)
    filtered = remove_cache_columns(filter(gate, df))
    @test size(filtered) == (3, 2)
    @test filtered.y == [1.1, 2.2, 3.3]
    @test gate == MemberGate(:x, 1..3.1)  # Make sure that equality holds for separate instances
end

@testset "Compound gates" begin
    df = DataFrame(
        x = [1, 5, 9, 12, 24],
        y = [-1, 5, -9, -12, 24]
    )
    g1 = SelectionGate(:x, 9)
    g2 = SelectionGate(:y, -12)

    f1 = remove_cache_columns(filter(g1 ∩ g2, df))
    @test size(f1) == (0, 2)
    f2 = remove_cache_columns(filter(g1 ∪ g2, df))
    @test size(f2) == (2, 2)
    @test f2.x == [9, 12]
    @test f2.y == [-9, -12]

    f3 = remove_cache_columns(filter(!g1, df))
    @test size(f3) == (4, 2)
    @test f3.x == [1, 5, 12, 24]

    @test filter(g1, df) == filter(g1 ∩ AlwaysGate(), df)
    @test filter(g2, df) == filter(g2 ∩ AlwaysGate(), df)

    # Invalid indices are ignored in UnionGates
    @test filter(g1, df) == filter(g1 ∪ SelectionGate(:z, 22), df)
end

@testset "Group gates" begin
    df = DataFrame(
        group = [1, 1, 1, 2, 2],
        x = [1, 2, 3, 1, 2],
        y = ["a", "a", "b", "a", "c"]
    )

    g1 = GroupGate(@gate(x == 1), :group, 1)
    @test nrow(filter(g1, df)) == 5

    g2 = GroupGate(@gate(x == 3), :group, 1)
    @test nrow(filter(g2, df)) == 3

    g3 = GroupGate(@gate(x == 5), :group, 1)
    @test nrow(filter(g3, df)) == 0

    g4 = GroupGate(@gate(y == "a"), :group, 2)
    @test nrow(filter(g4, df)) == 3

    g5 = GroupGate(@gate(y == "a"), :group, 1:2)
    @test nrow(filter(g5, df)) == 5
end

@testset "macro" begin
    df = DataFrame(
        x = [4, 3, 2, 1],
        y = [2, 3, 5, 7],
        z = [3, 1, 4, 1]
    )
    g1 = @gate x in 2..3 && z == 1
    f1 = remove_cache_columns(filter(g1, df))
    @test size(f1) == (1, 3)
    @test only(f1.y) == 3

    g2 = @gate g1 || y == 7
    f2 = remove_cache_columns(filter(g2, df))
    @test size(f2) == (2, 3)
    @test f2.y == [3, 7]

    g3 = @gate (x in 3..4 || y in 2.5..6.2) && z in 1:5
    f3 = remove_cache_columns(filter(g3, df))
    @test size(f3) == (3, 3)
    @test f3.z == [3, 1, 4]

    g4 = @gate (x != 4)
    f4 = remove_cache_columns(filter(g4, df))
    @test size(f4) == (3, 3)
    @test f4.x == [3, 2, 1]
    @test f4.y == [3, 5, 7]

    @test @gate() == AlwaysGate()
end

@testset "isapplicable" begin
    df = DataFrame(
        yes = ["y", "e", "s"]
    )

    @test isapplicable(@gate(yes == "x"), df)
    @test !isapplicable(@gate(no == "n"), df)

    @test isapplicable(@gate(yes in ["a"]), df)
    @test isapplicable(@gate(yes in ["a"]), df)
end

@testset "Unitful" begin
    df = DataFrame(
        x = [1, 2, 3, 4]u"s",
        y = [1, 2, 3, 4]
    )
    f1 = filter(@gate(x == 1u"s"), df)
    @test length(f1.y) == 1
    @test only(f1.y) == 1

    f2 = filter(@gate(x >= 3u"s"), df)
    @test length(f2.y) == 2
    @test f2.y == [3, 4]
end