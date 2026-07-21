struct PerGroup{G <: AbstractGate, F}
    condition::G  # What condition they must fulfill
    cols::Vector{Symbol}  # The columns used to make the groups
    aggregator::F  # either `any` or `all`, how many row must respect the condition
end

PerGroup(condition, cols::Symbol, aggregator) = PerGroup(condition, [cols], aggregator)

@memoize Dict function selectedby(gate::PerGroup, grouped::GroupedDataFrame)
    groups = combine(grouped) do group
        (; selected = gate.aggregator(gate.condition, eachrow(group)))
    end
    return groups.selected
end

function Base.filter(gate::PerGroup, grouped::GroupedDataFrame)
    @assert all(Symbol.(gate.cols) .== Symbol.(grouped.cols))
    groups = grouped[selectedby(gate, grouped)]
    return groups
end

function Base.filter(gate::PerGroup, df::AbstractDataFrame)
    groups = filter(gate, groupby(df, gate.cols))
    return DataFrames.combine(groups, All())
end
