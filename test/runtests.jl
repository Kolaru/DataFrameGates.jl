using DataFrameGates
using DataFrames
using Intervals
using Test

@testset "Basic gates" begin
    df = DataFrame(
        x = [1, 2, 3, 4, 5],
        y = [1.1, 2.2, 3.3, 4.4, 5.5]
    )

    gate = SelectionGate(:x, 3)  
    filtered = filter(gate, df)
    @test size(filtered) == (1, 2)
    @test only(filtered.y) == 3.3
    @test gate == SelectionGate(:x, 3)  # Make sure that equality holds for separate instances

    gate = MemberGate(:y, [2.2, 5.5])
    filtered = filter(gate, df)
    @test size(filtered) == (2, 2)
    @test filtered.x == [2, 5]
    @test gate == MemberGate(:y, [2.2, 5.5])  # Make sure that equality holds for separate instances

    gate = MemberGate(:x, 1..3.1)
    filtered = filter(gate, df)
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

    f1 = filter(g1 ∩ g2, df)
    @test size(f1) == (0, 2)
    f2 = filter(g1 ∪ g2, df)
    @test size(f2) == (2, 2)
    @test f2.x == [9, 12]
    @test f2.y == [-9, -12]

    f3 = filter(!g1, df)
    @test size(f3) == (4, 2)
    @test f3.x == [1, 5, 12, 24]
end

@testset "macro" begin
    df = DataFrame(
        x = [4, 3, 2, 1],
        y = [2, 3, 5, 7],
        z = [3, 1, 4, 1]
    )
    g1 = @gate x in 2..3 && z == 1
    f1 = filter(g1, df)
    @test size(f1) == (1, 3)
    @test only(f1.y) == 3

    g2 = @gate g1 || y == 7
    f2 = filter(g2, df)
    @test size(f2) == (2, 3)
    @test f2.y == [3, 7]

    g3 = @gate (x in 3..4 || y in 2.5..6.2) && z in 1:5
    f3 = filter(g3, df)
    @test size(f3) == (3, 3)
    @test f3.z == [3, 1, 4]
end