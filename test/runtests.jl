# Test each op and gradients, along with some combinations
# (TODO) Needs a much cleaner design long term
using cg
using Base.Test
using Base

show_test(test::AbstractString) = println("==============\n Running tests $test\n==============")
i = () -> cg.placeholder([1]) # Shape doesn't matter yet
c = cg.constant

function genarg(shape::AbstractArray, filltype::Symbol ; offset = 0, rand_offset = -0.5)
    if filltype == :range
        # val[j] = i + j
        return reshape(collect(Float64, 1:(*(shape...))), shape...) + offset
    elseif filltype == :rand
        return rand(shape...) + rand_offset
    elseif filltype == :ones
        return ones(shape...)
    else
        @assert false && "invalid filltype"
    end
end

function get_inputs(n::cg.Node)
    G = cg.get_graph([n])
    inputs = filter(x -> isa(x.op, cg.Placeholder), G.nodes)
    collect(inputs)
end


function test_output(out::cg.Node, truth::Function, args::Tuple{cg.Node, Array{Float64, 2}}...)
    # Float64/2 should be TensorValue once type system updated
    session = cg.Session(out)
    for (node, value) in args
        session.values[node] = value
    end
    graphresult = cg.interpret(session, out)
    truthresult = truth([x[2] for x in args]...)
    @test_approx_eq_eps(graphresult, truthresult, 0.001)
end

# Test each operator
function test_gradients(out::cg.Node, shape=[5] ; filltype::Symbol=:range, iters=1, debug=false)
    inputs = get_inputs(out)
    gradients = cg.grad(out, inputs)

    session = cg.Session(out)
    for iter = 1:iters
        for (i,input) = enumerate(inputs)
            session.values[input] = genarg(shape, filltype, offset = i)
        end

        for (input,grad) = zip(inputs, gradients)
            numeric = cg.numeric_grad(session, out, input, 0.0000001)
            symbolic = cg.interpret(session, grad, debug=debug)
            if debug
                @show session.values[input]
                @show session.values[out]
                @show numeric
                @show symbolic
            end
            @test_approx_eq_eps(symbolic, numeric, 0.01)
            for i = 1:length(symbolic)
                @test_approx_eq_eps(symbolic[i], numeric[i], 0.0001)
            end
        end
    end
end

i = () -> cg.placeholder([1]) # Shape doesn't matter yet
function test_scalar_gradients()
    show_test("scalar")
    @show test_gradients(sum(i()))

    # Scalar ops
    @show test_gradients(sum(i() + i()))
    @show test_gradients(sum(i() - i()))
    @show test_gradients(sum(i() * i()))
    @show test_gradients(sum(i() / i()))
    @show test_gradients(sum(i() ^ cg.constant(3.0)))
    @show test_gradients(sum(cg.constant(3.0) ^ i()))

    @show test_gradients(sum(-i()))
    @show test_gradients(sum(sign(i())))
    @show test_gradients(sum(sign(i())), filltype=:rand, iters=100)
    @show test_gradients(sum(exp(i())))
    @show test_gradients(sum(log(i())))
    @show test_gradients(sum(sin(i())))
    @show test_gradients(sum(cos(i())))
    @show test_gradients(sum(abs(i())))

    @show test_gradients(sum(max(i(), i())))
    @show test_gradients(sum(max(i(), i())), filltype=:rand, iters=100)
    @show test_gradients(sum(min(i(), i())))
    @show test_gradients(sum(min(i(), i())), filltype=:rand, iters=100)

    @show test_gradients(sum(cg.sigmoid(i())))
end

function test_shape_gradients()
    show_test("shape")
    # Shape related ops
    shape = [10,15]
    ops = [cg.maximum, cg.sum]
    for op in ops
        @show op
        for graph in [sum(op(i())),
                      sum(op(i(), cg.constant(1))), sum(op(i(), cg.constant(2)))]
            for filltype = [:ones, :rand, :range]
                @show (op, graph, filltype)
                test_gradients(graph, shape, filltype=filltype, iters=100)
            end
        end
    end
end

function test_get_and_set_gradients()
    c = cg.constant
    show_test("get_and_set")
    @show test_gradients(cg.getindex(i(), c(4)))
    @show test_gradients(cg.getindex(cg.setindex(i(), c(3), c(1000)), c(3)))
    @show test_gradients(cg.getindex(cg.setindex(i(), c(3), c(1000)), c(2)))
end

function test_other_gradients()
    show_test("other gradients")
    a = cg.constant(rand(4,5))
    b = i()
    # Mat mul
    @show test_gradients(cg.sum(cg.matmul(cg.t(b), b)), [4, 3])
    @show test_gradients(cg.sum(cg.matmul(b, cg.t(b))), [4, 3])
    @show test_gradients(cg.sum(cg.matmul(cg.t(a), b)), [4, 3])
    @show test_gradients(cg.sum(cg.matmul(cg.t(b), a)), [4, 3])
end

function test_broadcast()
    show_test("Broadcast")
    i1 = i()
    subScalar = c(2.0) - i()
    divScalar =  i() / c(2.0)
    subVec = cg.broadcastop(cg.Sub(), c([1.0, 2.0, 3.0]), i())
    divVec = cg.broadcastop(cg.Div(), i(), c([1.0, 2.0, 3.0]))
    #@show test_output(add, (x) -> [10.0, 10.0] .+ x, (i1, [1.0]'))
    for test in [subScalar, divScalar, subVec, divVec]
        for filltype in [:ones, :range, :rand]
            @show test
            @show filltype
            @show test_gradients(cg.sum(test), [3,5], filltype=filltype)
        end
    end
end

function test_nn()
    show_test("nn")

    for filltype in [:ones, :rand]
        si1 = i()
        softmax = cg.softmax(si1)
        ssi1 = i()
        softmax_stable = cg.softmax_stable(ssi1)
        ci1 = i()
        ci2 = i()
        crossentropy = cg.crossentropy(ci1, ci2)
        sci1 = i()
        sci2 = i()
        softmax_crossentropy = cg.crossentropy(sci1, cg.softmax(sci2))

        softmax_t(x) = exp(x) ./ sum(exp(x), 1)
        crossentropy_t(p, q) = -sum(p .* log(q))
        softmax_crossentropy_t(p, q) = crossentropy_t(p, softmax_t(q))
        shape = [5,10]
        a1 = genarg(shape, :rand, rand_offset=0)
        a2 = genarg(shape, :rand, rand_offset=0)

        @show test_output(softmax, softmax_t, (si1, a1))
        @show test_output(softmax_stable, softmax_t, (ssi1, a1))
        @show test_output(crossentropy, crossentropy_t, (ci1, a1), (ci2, a2))
        @show test_output(softmax_crossentropy, softmax_crossentropy_t, (sci1, a1), (sci2, a2))

        @show test_gradients(cg.sum(broadcast("/", si1, sum(si1, cg.constant(1)))))
        @show test_output(print(cg.sum(broadcast("/", si1, sum(si1)))), x -> sum(x / sum(x)), (si1, a1))

        @show test_gradients(cg.sum(broadcast("/", si1, sum(si1))))
        @show test_gradients(cg.getindex(si1, cg.constant(1)))
        @show test_gradients(sum(si1))

        scal1 = i()
        scal2 = i()
        @show test_gradients(scal1 / (scal1 + scal2), [1])
        @show test_gradients(cg.getindex(broadcast("/", si1, sum(si1)), cg.constant(1)), [2])

        @show test_gradients(cg.sum(softmax))
        @show test_gradients(cg.sum(softmax_stable))
        @show test_gradients(cg.sum(crossentropy))
        @show test_gradients(cg.sum(softmax_crossentropy))
    end
end

function test_sgd_basics()
    show_test("sgd")
    # Test basic optimization - minimize sum((b - a)^2)
    target = rand(10)
    a = cg.constant(target, "a")
    b = cg.variable(cg.constant(zeros(10)), "b") # Parameter to optimize
    c = b - a
    d = c * c
    e = sum(d)
    values = Dict{cg.Node, cg.TensorValue}()
    optimizer = cg.sgd_optimizer(e, [b], cg.constant(0.001, "step_size"))
    #cg.render(cg.get_graph([b]), "graph.png")
    session = cg.Session(optimizer)
    for i = 1:10000
        cg.interpret(session, optimizer)
        if session.values[e][1] <= 0.001
            break
        end
    end
    @test_approx_eq_eps target session.values[b] 0.1
end

# Test that sum gradients work properly
function test_sum()
    show_test("sum")
    @show test_gradients(cg.sum(i()), [3, 5])
    a = cg.placeholder([3, 5])
    b = cg.sum(a, cg.constant(1))
    c = cg.sum(b)
    @show test_gradients(c, [3, 5])
end


test_other_gradients()
test_sum()
test_broadcast()
test_nn()
test_scalar_gradients()
test_shape_gradients()
test_get_and_set_gradients()
test_sgd_basics()
