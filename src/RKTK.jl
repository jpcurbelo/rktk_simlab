println(raw"                ______ _   _______ _   __")
println(raw"                | ___ \ | / /_   _| | / /   Version  2.2")
println(raw"                | |_/ / |/ /  | | | |/ /")
println(raw"                |    /|    \  | | |    \   David K. Zhang")
println(raw"                | |\ \| |\  \ | | | |\  \     (c) 2019")
println(raw"                |_| \_\_| \_/ |_| |_| \_/")
println()
println("RKTK is free software distributed under the terms of the MIT license.")
println()
flush(stdout)

################################################################################

using Printf
using UUIDs

push!(LOAD_PATH, @__DIR__)
using DZMisc
using DZOptimization
using MultiprecisionFloats
using RKTK2

################################################################################

numstr(x) = @sprintf("%#-18.12g", BigFloat(x))
shortstr(x) = @sprintf("%#.5g", BigFloat(x))
score_str(x) = lpad(string(clamp(round(Int,
    -100 * log10(BigFloat(x))), 0, 9999)), 4, '0')
rktk_filename(opt, id) = score_str(opt.objective[1]) * '-' *
    score_str(norm(opt.gradient)) * "-RKTK-" * uppercase(string(id)) * '-' *
    lpad(string(opt.iteration[1]), 10, '0') * ".txt"

function print_help()
    say("Usage: julia RKTK.jl <mode> [parameters...]")
    say()
    say("RKTK provides the following <mode> options:")
    say("    search <order> <num-stages> <precision>")
    say()
end

function print_table_header()
    say(" Iteration │  Objective value  │   Gradient norm   │",
                    "  Last step size   │    Point norm     │ Type")
    say("───────────┼───────────────────┼───────────────────┼",
                    "───────────────────┼───────────────────┼──────")
end

function print_table_row(iter, obj_value, grad_norm,
                         step_size, point_norm, type)
    say(" ", lpad(string(iter), 9, ' '), " | ",
        numstr(obj_value), "│ ", numstr(grad_norm),  "│ ",
        numstr(step_size), "│ ", numstr(point_norm), "│ ", type)
end

function rmk_table_row(iter, obj_value, grad_norm,
                       step_size, point_norm, type)
    rmk(" ", lpad(string(iter), 9, ' '), " | ",
        numstr(obj_value), "│ ", numstr(grad_norm),  "│ ",
        numstr(step_size), "│ ", numstr(point_norm), "│ ", type)
end

function print_table_row(opt, type)
    print_table_row(opt.iteration[1], opt.objective[1], norm(opt.gradient),
                    opt.last_step_size[1], norm(opt.current_point), type)
end

function rmk_table_row(opt, type)
    rmk_table_row(opt.iteration[1], opt.objective[1], norm(opt.gradient),
                  opt.last_step_size[1], norm(opt.current_point), type)
end

################################################################################

function rkoc_optimizer(::Type{T}, order::Int, num_stages::Int) where {T <: Real}
    obj_func, grad_func = rkoc_explicit_backprop_functors(T, order, num_stages)
    num_vars = div(num_stages * (num_stages + 1), 2)
    x_init = T.(rand(BigFloat, num_vars))
    BFGSOptimizer(x_init, inv(T(1_000_000)), obj_func, grad_func)
end

################################################################################

function save_to_file(opt, id)
    name = rktk_filename(opt, id)
    rmk("Saving progress to file ", name, "...")
    file = open(rktk_filename(opt, id), "w")
    for x in opt.current_point
        write(file, string(BigFloat(x)), '\n')
    end
    close(file)
    rmk("Save complete.")
end

function search(::Type{T}, order::Int, num_stages::Int) where {T <: Real}
    while true
        id = uuid4()
        say("Running ", T, " search RKTK-", uppercase(string(id)), ".\n")
        print_table_header()
        optimizer = rkoc_optimizer(T, order, num_stages)
        print_table_row(optimizer, "NONE")
        # save_to_file(optimizer, id)
        last_print_time = last_save_time = time_ns()
        while true
            bfgs_used, objective_decreased = step!(optimizer)
            if !objective_decreased
                print_table_row(optimizer, "DONE")
                save_to_file(optimizer, id)
                say("\nCompleted search RKTK-", uppercase(string(id)), ".\n")
                break
            end
            current_time = time_ns()
            if current_time - last_save_time > UInt(60_000_000_000)
                save_to_file(optimizer, id)
                last_save_time = current_time
            end
            if !bfgs_used
                print_table_row(optimizer, "GRAD")
                last_print_time = current_time
            elseif current_time - last_print_time > UInt(80_000_000)
                rmk_table_row(optimizer, "BFGS")
                last_print_time = current_time
            end
        end
    end
end

################################################################################

if (length(ARGS) == 0) || ("-h" in ARGS) || ("--help" in ARGS)
    print_help()
elseif uppercase(ARGS[1]) == "SEARCH"
    order = parse(Int, ARGS[2])
    num_stages = parse(Int, ARGS[3])
    prec = parse(Int, ARGS[4])
    setprecision(prec)
    if     prec == 32;  search(Float32,   order, num_stages)
    elseif prec == 64;  search(Float64,   order, num_stages)
    elseif prec == 128; search(Float64x2, order, num_stages)
    elseif prec == 192; search(Float64x3, order, num_stages)
    elseif prec == 256; search(Float64x4, order, num_stages)
    elseif prec == 320; search(Float64x5, order, num_stages)
    elseif prec == 384; search(Float64x6, order, num_stages)
    elseif prec == 448; search(Float64x7, order, num_stages)
    elseif prec == 512; search(Float64x8, order, num_stages)
    else;               search(BigFloat,  order, num_stages)
    end
else
    print_help()
end

# const AccurateReal = Float64x4
# const THRESHOLD = AccurateReal(1e-40)

# function constrain(x::Vector{T}, evaluator::RKOCEvaluator{T}) where {T <: Real}
#     x_old, obj_old = x, norm2(evaluator(x))
#     while true
#         direction = qr(evaluator'(x_old)) \ evaluator(x_old)
#         x_new = x_old - direction
#         obj_new = norm2(evaluator(x_new))
#         if obj_new < obj_old
#             x_old, obj_old = x_new, obj_new
#         else
#             break
#         end
#     end
#     x_old, obj_old
# end

# function compute_order(x::Vector{T}, threshold::T) where {T <: Real}
#     num_stages = compute_stages(x)
#     order = 2
#     while true
#         rmk("    Testing constraints for order ", order, "...")
#         x_new, obj_new = constrain(x,
#             RKOCEvaluator{AccurateReal}(order, num_stages))
#         if obj_new <= threshold^2
#             x = x_new
#             order += 1
#         else
#             break
#         end
#     end
#     x, order - 1
# end

# function drop_last_stage(x::Vector{T}) where {T <: Real}
#     num_stages = compute_stages(x)
#     vcat(x[1 : div((num_stages - 1) * (num_stages - 2), 2)],
#          x[div(num_stages * (num_stages - 1), 2) + 1 : end - 1])
# end

# ################################################################################

# # function objective(x)
# #     x[end]^2
# # end

# # function gradient(x)
# #     result = zero(x)
# #     result[end] = dbl(x[end])
# #     result
# # end

# function constrain_step(x, step, evaluator)
#     constraint_jacobian = copy(transpose(evaluator'(x)))
#     orthonormalize_columns!(constraint_jacobian)
#     step - constraint_jacobian * (transpose(constraint_jacobian) * step)
# end

# function constrained_step_value(step_size,
#         x, step_direction, step_norm, evaluator, threshold)
#     x_new, obj_new = constrain(
#         x - (step_size / step_norm) * step_direction, evaluator)
#     if obj_new < threshold
#         objective(x_new)
#     else
#         AccurateReal(NaN)
#     end
# end

# ################################################################################

# struct ConstrainedBFGSOptimizer{T}
#     objective_value::Ref{T}
#     last_step_size::Ref{T}
# end

# ################################################################################

# if length(ARGS) != 1
#     say("Usage: julia StageReducer.jl <input-file>")
#     exit()
# end

# const INPUT_POINT = AccurateReal.(BigFloat.(split(read(ARGS[1], String))))
# say("Successfully read input file: " * ARGS[1])

# const NUM_VARS = length(INPUT_POINT)
# const NUM_STAGES = compute_stages(INPUT_POINT)
# const REFINED_POINT, ORDER = compute_order(INPUT_POINT, THRESHOLD)
# say("    ", NUM_STAGES, "-stage method of order ", ORDER,
#     " (refined by ", approx_norm(REFINED_POINT - INPUT_POINT), ").")

# const FULL_CONSTRAINTS = RKOCEvaluator{AccurateReal}(ORDER, NUM_STAGES)
# const ACTIVE_CONSTRAINT_INDICES, HI, LO = linearly_independent_column_indices!(
#     copy(transpose(FULL_CONSTRAINTS'(INPUT_POINT))), THRESHOLD)
# const ACTIVE_CONSTRAINTS = RKOCEvaluator{AccurateReal}(
#     ACTIVE_CONSTRAINT_INDICES, NUM_STAGES)
# say("    ", ACTIVE_CONSTRAINTS.num_constrs, " out of ",
#     FULL_CONSTRAINTS.num_constrs, " active constraints.")
# say("    Constraint thresholds: [",
#     shortstr(-log2(BigFloat(LO))), " | ",
#     shortstr(-log2(BigFloat(THRESHOLD))), " | ",
#     shortstr(-log2(BigFloat(HI))), "]")
# say()

# const ERROR_EVALUATOR = RKOCEvaluator{AccurateReal}(
#     Vector{Int}(rooted_tree_count(ORDER) + 1 : rooted_tree_count(ORDER + 1)),
#     NUM_STAGES)

# function objective(x)
#     norm2(ERROR_EVALUATOR(x))
# end

# function gradient(x)
#     dbl.(transpose(ERROR_EVALUATOR'(x)) * ERROR_EVALUATOR(x))
# end

# const OPT = ConstrainedBFGSOptimizer{AccurateReal}(
#     objective(REFINED_POINT),
#     AccurateReal(0.00001))




# function main()
#     x = copy(REFINED_POINT)
#     inv_hess = Matrix{AccurateReal}(I, NUM_VARS, NUM_VARS)

#     cons_grad = constrain_step(x, gradient(x), ACTIVE_CONSTRAINTS)
#     cons_grad_norm = norm(cons_grad)
#     print_table_header()
#     print_table_row(OPT.objective_value[], cons_grad_norm, 0, "NONE")

#     while true

#         rmk("Performing gradient descent step...")
#         grad_step_size, obj_grad = quadratic_search(constrained_step_value,
#             OPT.last_step_size[], x, cons_grad, cons_grad_norm,
#             ACTIVE_CONSTRAINTS, THRESHOLD)

#         rmk("Performing BFGS step...")
#         bfgs_step = constrain_step(x, inv_hess * cons_grad, ACTIVE_CONSTRAINTS)
#         bfgs_step_norm = norm(bfgs_step)
#         bfgs_step_size, obj_bfgs = quadratic_search(constrained_step_value,
#             OPT.last_step_size[], x, bfgs_step, bfgs_step_norm,
#             ACTIVE_CONSTRAINTS, THRESHOLD)

#         rmk("Line searches complete.")
#         if obj_bfgs < OPT.objective_value[] && obj_bfgs <= obj_grad
#             x, _ = constrain(x - (bfgs_step_size / bfgs_step_norm) * bfgs_step,
#             ACTIVE_CONSTRAINTS)
#             cons_grad_new = constrain_step(x, gradient(x), ACTIVE_CONSTRAINTS)
#             cons_grad_norm_new = norm(cons_grad_new)
#             update_inverse_hessian!(inv_hess,
#                 -bfgs_step_size / bfgs_step_norm,
#                 bfgs_step,
#                 cons_grad_new - cons_grad,
#                 Vector{AccurateReal}(undef, NUM_VARS))
#             OPT.last_step_size[] = bfgs_step_size
#             OPT.objective_value[] = obj_bfgs
#             cons_grad = cons_grad_new
#             cons_grad_norm = cons_grad_norm_new
#             print_table_row(OPT.objective_value[], cons_grad_norm,
#                 OPT.last_step_size[], "")
#         elseif obj_grad < OPT.objective_value[]
#             x, _ = constrain(x - (grad_step_size / cons_grad_norm) * cons_grad,
#                 ACTIVE_CONSTRAINTS)
#             inv_hess = Matrix{AccurateReal}(I, NUM_VARS, NUM_VARS)
#             OPT.last_step_size[] = grad_step_size
#             OPT.objective_value[] = obj_grad
#             cons_grad = constrain_step(x, gradient(x), ACTIVE_CONSTRAINTS)
#             cons_grad_norm = norm(cons_grad)
#             print_table_row(OPT.objective_value[], cons_grad_norm,
#                 OPT.last_step_size[], "GRAD")
#         else
#             print_table_row(OPT.objective_value[], cons_grad_norm, 0, "DONE")
#             say()
#             break
#         end

#     end

#     println.(string.(BigFloat.(x)))

#     # x_new = drop_last_stage(x)
#     # println.(string.(BigFloat.(x_new)))
# end

# main()
