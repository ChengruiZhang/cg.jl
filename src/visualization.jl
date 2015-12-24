##################
# Representation #
##################
import Base.show

function Base.show(io::IO, node::Node)
    parts = Vector{AbstractString}()
    push!(parts, "name: $(node.name)")
    push!(parts, "op: $(node.op)")
    if length(node.inputs) > 0
        push!(parts, "inputs: $(join([x.name for x = node.inputs], ", "))")
    end
    if length(node.outputs) > 0
        push!(parts, "outputs: $(join([x.name for x = node.outputs], ", "))")
    end

  print(io, "Node{$(join(parts, " || "))}")
end

# Print connected component of node
function to_dot(G::Graph)
    nodeIds = Dict{Node, Int}()
    id = 0
    for node in G.nodes
        nodeIds[node] = id
        id += 1
    end

    labels = Vector{AbstractString}()
    edges = Vector{AbstractString}()
    for node in G.nodes
        thisId = nodeIds[node]
        #shape = isa(node, Operation) ? "box" : "ellipse"
        shape = "ellipse"
        labelLine = string(thisId, " [shape=\"", shape,"\", label=\"", tostring(node), "\"];")
        push!(labels, labelLine)
        for next in succ(node)
            edge = "$(nodeIds[node]) -> $(nodeIds[next]);"
            push!(edges, edge)
        end
    end

    string("digraph computation {\n",
           join(labels,"\n"),
           "\n",
           join(edges,"\n"),
           "\n}"
           )
end

function render(G::Graph, outfile::AbstractString)
    dotstr = to_dot(G)
    dotcmd = `dot -Tpng -o $(outfile)`
    run(pipeline(`echo $(dotstr)`, dotcmd))
end

function tostring(node::Node)
    # TODO - include values for constants
    return "$(node.name): $(typeof(node.op))"
end

function tostring(nodes::Vector{Node})
    c = ", "
    "[$(join(map(tostring, nodes), c))]"
end

# Pretty print a computation
function pprint(g::Graph)

end
