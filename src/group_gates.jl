struct Count{T} <: Function
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

(gate::GroupGate)(group) = gate.aggregator(gate.condition.(eachrow(group)))

function Base.show(io::IO, gate::GroupGate ; indent = 0)
    println(io, " "^indent * "GroupGate on columns $(gate.cols) requiring $(gate.aggregator) with condition")
    println(io, gate.condition)
end

idstring(gate::GroupGate) = "_group_gate_$(join(string.(gate.cols), "_"))_$(gate.condition)_$(gate.aggregator)"

function selectedby(gate::GroupGate, grouped::GroupedDataFrame)
    groups = combine(grouped) do group
        (; selected = gate.aggregator(gate.condition.(eachrow(group))))
    end
    return groups.selected
end

function _selectedby(gate::GroupGate, df::AbstractDataFrame)
    auxiliary = DataFrame(
        :group => groupby(df, gate.cols).groups,
        :passing => selectedby(gate.condition, df)
    )
    groups = combine(groupby(auxiliary, :group),
        :group,
        :passing => gate.aggregator => :selected
    )
    return groups.selected
end

#== Compound GroupGate gates ==#
struct GroupGateIntersection <: AbstractGroupGate
    gates::Vector{AbstractGroupGate}
    cols::Vector{Symbol}
end

function Base.show(io::IO, gate::GroupGateIntersection ; indent = 0)
    println(io, " "^indent * "GroupGateInteresection on columns $(gate.cols) with subgates")
    for gate in gate.gates
        show(io, gate ; indent = indent + 2)
    end
end

function Base.intersect(gates::Vararg{AbstractGroupGate})
    cols = unique(gate.cols for gate in gates)
    if length(cols) != 1
        throw(ArgumentError("The GroupGate must all use the same grouping column, found $cols"))
    end

    return GroupGateIntersection(collect(gates), gates[1].cols)
end

idstring(gate::GroupGateIntersection) = "_group_gate_intersection_$(join(string.(gate.cols), "_"))_$(join(idstring.(gate.gates)))"

function selectedby(gate::GroupGateIntersection, grouped::GroupedDataFrame)
    return reduce((.&), selectedby.(gate.gates, Ref(grouped)))
end

function _selectedby(gate::GroupGateIntersection, df::AbstractDataFrame)
    return reduce((.&), selectedby.(gate.gates, Ref(df)))
end

#== Functionalities ==#
function Base.filter(gate::AbstractGroupGate, grouped::GroupedDataFrame)
    error("This should not be reached")
    @assert all(Symbol.(gate.cols) .== Symbol.(grouped.cols))
    groups = grouped[selectedby(gate, grouped)]
    return groups
end