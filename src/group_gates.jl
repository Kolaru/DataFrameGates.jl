struct Count{T}
    allowed::T
end

(c::Count)(array) = (count(array) in c.allowed)

abstract type AbstractGroupGate end

struct GroupGate{G <: AbstractGate, F} <: AbstractGroupGate
    condition::G  # What condition they must fulfill
    cols::Vector{Symbol}  # The columns used to make the groups
    aggregator::F  # either `any`, `all`, a number or a list of numbers, representing how many row must respect the condition
end

GroupGate(condition, cols::Symbol, aggregator) = GroupGate(condition, [cols], aggregator)
GroupGate(condition, cols::Symbol, n::Int) = GroupGate(condition, cols, Count(n))
GroupGate(condition, cols::Symbol, allowed::AbstractVector) = GroupGate(condition, cols, Count(allowed))

(gate::GroupGate)(values) = gate.aggregator(gate.condition.(eachrow(group)))

function selectedby(gate::GroupGate, grouped::GroupedDataFrame)
    groups = combine(grouped) do group
        (; selected = gate.aggregator(gate.condition.(eachrow(group))))
    end
    return groups.selected
end

#== Compound GroupGate gates ==#
struct GroupGateIntersection <: AbstractGroupGate
    gates::Vector{AbstractGroupGate}
    cols::Vector{Symbol}
end

function Base.intersect(gates::Vararg{AbstractGroupGate})
    cols = unique(gate.cols for gate in gates)
    if length(cols) != 1
        throw(ArgumentError("The GroupGate must all use the same grouping column, found $cols"))
    end

    return GroupGateIntersection(collect(gates), gates[1].cols)
end

function selectedby(gate::GroupGateIntersection, grouped::GroupedDataFrame)
    return reduce((.&), selectedby.(gate.gates, Ref(grouped)))
end

#== Functionalities ==#
function Base.filter(gate::AbstractGroupGate, grouped::GroupedDataFrame)
    @assert all(Symbol.(gate.cols) .== Symbol.(grouped.cols))
    groups = grouped[selectedby(gate, grouped)]
    return groups
end

function Base.filter(gate::AbstractGroupGate, df::AbstractDataFrame)
    groups = filter(gate, groupby(df, gate.cols))
    return DataFrames.combine(groups, All())
end