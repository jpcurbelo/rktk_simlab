println(raw"                ______ _   _______ _   __")
println(raw"                | ___ \ | / /_   _| | / /   Version  2.3")
println(raw"                | |_/ / |/ /  | | | |/ /")
println(raw"                |    /|    \  | | |    \   David K. Zhang")
println(raw"                | |\ \| |\  \ | | | |\  \     (c) 2022")
println(raw"                |_| \_\_| \_/ |_| |_| \_/")
println()
println("RKTK is free software distributed under the terms of the MIT license.")
println()
flush(stdout)

################################################################################

using Base.Threads: @threads, nthreads, threadid
using Printf: @sprintf
using Statistics: mean, std
using UUIDs: UUID, uuid4

using DZOptimization
using DZOptimization: norm
using MultiFloats
using RungeKuttaToolKit

push!(LOAD_PATH, @__DIR__)
using DZMisc

set_zero_subnormals(true)
use_standard_multifloat_arithmetic()

## Jesus
using Printf

################################################################################

function precision_type(prec::Int)::Type
    if     prec <= 32;  Float32
    elseif prec <= 64;  Float64
    elseif prec <= 128; Float64x2
    elseif prec <= 192; Float64x3
    elseif prec <= 256; Float64x4
    elseif prec <= 320; Float64x5
    elseif prec <= 384; Float64x6
    elseif prec <= 448; Float64x7
    elseif prec <= 512; Float64x8
    else
        setprecision(prec)
        BigFloat
    end
end

approx_precision(::Type{Float32  }) = 32
approx_precision(::Type{Float64  }) = 64
approx_precision(::Type{Float64x2}) = 128
approx_precision(::Type{Float64x3}) = 192
approx_precision(::Type{Float64x4}) = 256
approx_precision(::Type{Float64x5}) = 320
approx_precision(::Type{Float64x6}) = 384
approx_precision(::Type{Float64x7}) = 448
approx_precision(::Type{Float64x8}) = 512
approx_precision(::Type{BigFloat }) = precision(BigFloat)

function Base.show(io::IO, ::Type{MultiFloat{Float64,N}}) where {N}
    write(io, "Float64x")
    show(io, N)
end

function Base.show(io::IO, ::Type{BigFloat})
    write(io, "BigFloat(")
    show(io, precision(BigFloat))
    write(io, ')')
end

################################################################################

struct RKTKID
    order::Int
    num_stages::Int
    uuid::UUID
end

function Base.show(io::IO, id::RKTKID)
    write(io, "RKTK-")
    write(io, lpad(id.order, 2, '0'))
    write(io, lpad(id.num_stages, 2, '0'))
    write(io, '-')
    write(io, uppercase(string(id.uuid)))
end

const RKTKID_REGEX = Regex(
    "RKTK-([0-9]{2})([0-9]{2})-([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-" *
    "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})")
const RKTK_FILENAME_REGEX = Regex(
    "^[0-9]{4}-[0-9]{4}-[0-9]{4}-RKTK-([0-9]{2})([0-9]{2})-([0-9A-Fa-f]{8}-" *
    "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\\.txt\$")


function find_rktkid(str::String)::Union{RKTKID,Nothing}
    """
    Extracts and parses the RKT Kid (Resource Key Token Kid) from a string.

    Arguments

    str::String: The input string to extract the RKT Kid from.

    Returns an instance of RKTKID if a valid RKT Kid is found in the input string, otherwise returns nothing.
    """

    println("filename $(str)")
    str = split(str, "/")[end]
    println("filename $(str)")
    
    m = match(RKTKID_REGEX, str)

    println("m = $(m)")
    if m !== nothing
        RKTKID(parse(Int, m[1]), parse(Int, m[2]), UUID(m[3]))
    else
        nothing
    end
end

function find_filename_by_id(dir::String, id::RKTKID)::Union{String,Nothing}
    """
    Finds a file in the specified directory with the given RKTKID.

    Parameters:
        dir (str): The directory to search in.
        id (RKTKID): The RKTKID of the file to find.

    Returns:
        str or None: The filename of the matching file if found, otherwise None.
    """

    result = nothing
    for filename in readdir(dir)
        m = match(RKTKID_REGEX, filename)
        if ((m !== nothing) && (parse(Int, m[1]) == id.order) &&
                (parse(Int, m[2]) == id.num_stages) && (UUID(m[3]) == id.uuid))
            if result !== nothing
                say("ERROR: Found multiple files with RKTK ID $id.")
                exit()
            else
                result = filename
            end
        end
    end
    result
end

################################################################################

function log_score(x)::Int
    bx = BigFloat(x)
    if     iszero(bx)  ; typemax(Int)
    elseif isfinite(bx); round(Int, -100 * log10(bx))
    else               ; 0
    end
end

function scaled_log_score(x)
    bx = BigFloat(x)
    if     iszero(bx)  ; typemax(Int)
    elseif isfinite(bx); round(Int, 10000 - 3333 * log10(bx) / 2)
    else               ; 0
    end
end

score_str(x)::String = lpad(clamp(log_score(x), 0, 9999), 4, '0')
scaled_score_str(x)::String = lpad(clamp(scaled_log_score(x), 0, 9999), 4, '0')

rktk_score_str(opt) = *(
    score_str(opt.current_objective_value[]),
    '-',
    score_str(norm(opt.current_gradient)),
    '-',
    scaled_score_str(norm(opt.current_point))
)

rktk_filename(opt, id::RKTKID)::String =
    rktk_score_str(opt) * '-' * string(id) * ".txt"

numstr(x)::String = @sprintf("%#-18.12g", BigFloat(x))
shortstr(x)::String = @sprintf("%#.5g", BigFloat(x))

function print_help()::Nothing
    """
    print_help()

    Prints a help message that describes how to use the RKToolbox program.
    """
    say("Usage: julia RKTK.jl <command> [parameters...]")
    say()
    say("RKTK provides the following <command> options:")
    say()
    say("    search <order> <num-stages> <precision>")
    say("        Runs an infinite search loop using the specified precision, order, and number of stages.")
    say()
    say("    refine <rktk-id> <precision>")
    say("        Refines an existing Runge-Kutta method with the specified ID to the given precision.")
    say()
    say("    clean <precision>")
    say("        Cleans all cached Runge-Kutta methods with the specified precision.")
    say()
    say("    benchmark <order> <num-stages> <benchmark-secs> <num-trials>")
    say("        Runs benchmarks on Runge-Kutta methods with the specified order, number of stages, and floating-point types.")
    say()
end

function print_table_header()::Nothing
    say(" Iteration │  Objective value  │   Gradient norm   │",
                    "  Last step size   │    Point norm     │ Type")
    say("───────────┼───────────────────┼───────────────────┼",
                    "───────────────────┼───────────────────┼──────")
end

function print_table_row(iter, obj_value, grad_norm,
                         step_size, point_norm, type)::Nothing
    """
    Prints a single row of a table summarizing optimization progress, with columns for the current iteration,
    objective function value, gradient norm, step size, point norm, and optimization method type.

    Args:
        iter: An integer representing the current iteration.
        obj_value: A floating-point number representing the current objective function value.
        grad_norm: A floating-point number representing the norm of the current gradient.
        step_size: A floating-point number representing the step size taken in the current iteration.
        point_norm: A floating-point number representing the norm of the current point.
        type: A string representing the optimization method type.

    Returns:
        Nothing
    """

    say("a ", lpad(iter, 9, ' '), " | ",
        numstr(obj_value), "│ ", numstr(grad_norm),  "│ ",
        numstr(step_size), "│ ", numstr(point_norm), "│ ", type)

    # str = @sprintf("b %9d | %14.4e │ %14.4e │ %14.4e │ %14.4e │ %s", iter, obj_value, grad_norm, step_size, point_norm, type)
    # print(str)

end

function rmk_table_row(iter, obj_value, grad_norm,
                       step_size, point_norm, type)::Nothing
    rmk(" ", lpad(iter, 9, ' '), " | ",
        numstr(obj_value), "│ ", numstr(grad_norm),  "│ ",
        numstr(step_size), "│ ", numstr(point_norm), "│ ", type)
end

function print_table_row(opt, type)::Nothing
    """
    Prints a single row of a table summarizing optimization progress, with columns for the current iteration,
    objective function value, gradient norm, step size, point norm, and optimization method type.
    
    Args:
        opt: An optimization object with the current iteration count, current objective value, current gradient, 
            last step size, and current point.
        type: A string representing the optimization method type.
    
    Returns:
        Nothing
    """
    print_table_row(opt.iteration_count[], opt.current_objective_value[],
                    norm(opt.current_gradient),
                    opt.last_step_size[1], norm(opt.current_point), type)
end

function rmk_table_row(opt, type)::Nothing
    rmk_table_row(opt.iteration_count[], opt.current_objective_value[],
                  norm(opt.current_gradient),
                  opt.last_step_size[1], norm(opt.current_point), type)
end

################################################################################
## for SEARCH
function rkoc_optimizer(::Type{T}, order::Int, num_stages::Int,
        x_init::Vector{BigFloat}, num_iters::Int) where {T <: Real}
    """   
    Create an optimizer for the RKOC (Runge-Kutta Optimized Controller) algorithm with the given parameters.
    
    # Arguments
    - `T`: Type of the number to use in the optimization. 
    - `order`: The order of accuracy for the RKOC method. 
    - `num_stages`: The number of stages to use in the RKOC method. 
    - `x_init`: An initial guess for the optimization variables. 
    - `num_iters`: Maximum number of iterations for the optimization. 
    
    # Returns
    An instance of the BFGSOptimizer type, which can be used to run the optimization.

    """

    ## homefolder/.julia/packages/RungeKuttaToolKit/JsRGa/src/RungeKuttaToolKit.jl:1237
    ## ("RungeKuttaToolKit") Objective and gradient functors for the RKOC method with the given T, order and num_stages.
    obj_func, grad_func = rkoc_explicit_backprop_functors(T, order, num_stages)
    
    # println(obj_func)
    # println(grad_func)
    
    num_vars = div(num_stages * (num_stages + 1), 2)
    @assert length(x_init) == num_vars

    ## ("DZOptimization")
    opt = BFGSOptimizer(obj_func, grad_func, T.(x_init), inv(T(1_000_000)))
    # println(opt)

    opt.iteration_count[] = num_iters
    opt
end

## for REFINE???
function rkoc_optimizer(::Type{T}, id::RKTKID,
                        filename::String) where {T <: Real}

    """
    Applies a Runge-Kutta optimal control method to optimize the given objective 
    function using a trajectory of time-dependent solutions from a file named 
    `filename`. Returns a tuple of the solution and the trajectory header.
    
    # Arguments
    - `T`: The element type for the numerical values. Must be a subtype of `Real`.
    - `id`: The identifier for the Runge-Kutta optimal control method. Must be of 
            type `RKTKID`.
    - `filename`: The name of the file containing the trajectory of time-dependent 
                    solutions.
    
    # Returns
    - A tuple of '(solution, header)' where 'solution' is the solution to the 
        optimization problem and 'header' is a 'Vector{String}' cosplitntaining the 
        parsed header information from the trajectory.
    """


    # println("filename $(filename)")
    # filename = split(filename, "/")[end]
    # println("filename $(filename)")

    trajectory = filter(!isempty, strip.(split(read(filename, String), "\n\n")))
    point_data = filter(!isempty, strip.(split(trajectory[end], '\n')))
    header = split(point_data[1])
    x_init = BigFloat.(point_data[2:end])
    num_iters = parse(Int, header[1])
    rkoc_optimizer(T, id.order, id.num_stages, x_init, num_iters), header
end

################################################################################
function create_directory(order::Int, num_stages::Int)
    """
    Creates a directory with a specific format to store the files before creating them.

    Args:
        order (Int): The order of the simulation.
        num_stages (Int): The number of stages of the simulation.
    
    Returns:
        folder_name (String): The name of the created folder.
    """

    folder_name = "RKTK_order_$(order)_num_stages$(num_stages)_precisionFloat$(precision(BigFloat))"
    
    # create folder if it does not exist
    if !isdir(folder_name)
        mkdir(folder_name)
    end
    
    return folder_name
end


function save_to_file(opt, id::RKTKID, folder_path::AbstractString)
    """   
    Saves the progress of optimization to a file with the given ID. The file contains
    the iteration count, precision, objective value, gradient norm, and current point.
    If a file with the same ID already exists, the function checks if the new
    optimization progress is better than the one saved in the file. If the new progress
    is not better, no save is necessary.
    
    Parameters:
        opt (BFGSOptimizer{T}): The optimizer object containing the current optimization progress.
        id (RKTKID): The ID to use for the file to be saved.
        T (Type{T}): The type of floating-point numbers to use in the optimization.
    Returns:
        None
    """

    # # Create folder if it does not exist
    # # folder_name = create_directory(id.order, id.num_stages)
    
    # # folder_name = "RKTK_order_$(id.order)_num_stages$(id.num_stages)_precisionFloat$(precision(BigFloat))"
    filename = joinpath(folder_path, rktk_filename(opt, id))

    # filename = rktk_filename(opt, id)

    rmk("Saving progress to file ", filename, "...\n")

    old_folder_name = replace(folder_path, "_clean" => "")
    println("old_folder_name = $(old_folder_name)")
    println("id = $(id)")

    old_filename = find_filename_by_id(old_folder_name, id)   ##"."

    println(old_filename)
    
    if old_filename !== nothing

        println("old_filename, filename", old_filename, filename)
        
        if old_filename != filename

            mv(old_filename, filename; force=true)

            # println("\n\ncp(old_filename, filename; force=true)")

            # cp(old_filename, filename; force=true)

            # old_dir = dirname(old_filename)
            # new_dir = dirname(filename)

            # if old_dir == new_dir
            #     # rename the file in the same directory
            #     mv(old_filename, filename; force=true)
            # else
            #     # copy the file to a new directory
            #     cp(old_filename, basename(filename); force=true)
        
            #     # delete the original file
            #     rm(old_filename)
            # end

            
        end
        trajectory = filter(!isempty,
            strip.(split(read(filename, String), "\n\n")))
        point_data = filter(!isempty, strip.(split(trajectory[end], '\n')))
        header = split(point_data[1])
        num_iters = parse(Int, header[1])
        prec = parse(Int, header[2])
        if (precision(BigFloat) <= prec) && (opt.iteration_count[] <= num_iters)
            rmk("No save necessary.")
            return
        end
    end

    if log_score(opt.current_objective_value[]) > 9999999   #999999999
        file = open(filename, "a+")
        println(file, opt.iteration_count[], ' ', precision(BigFloat), ' ',
                log_score(opt.current_objective_value[]), ' ', log_score(norm(opt.current_gradient)))

        for x in opt.current_point
            println(file, BigFloat(x))
        end
        println(file)
        close(file)
        rmk("Save complete.")
    end

end

const TERM = isa(stdout, Base.TTY)

## this!!!
function run!(opt, id::RKTKID) where {T <: Real}
    """
    Runs the optimization until convergence, periodically saving the results to a file.

    Args:
        opt: An object representing the optimization.
        id (RKTKID): An object representing the ID of the current RKTK simulation.
        T (Type{T}): The type of floating-point numbers to use in the optimization.
    """

    # print_table_header()
    # print_table_row(opt, "NONE")
    save_to_file(opt, id)
    
    last_print_time = last_save_time = time_ns()
   
   
    # file_counter = 1
    while true

        # println("\nfile_counter = $(file_counter)\n")
        # file_counter += 1


        ## homefolder/.julia/packages/DZOptimization/ENzlO/src/DZOptimization.jl
        step!(opt)
        if opt.has_converged[]
            # print_table_row(opt, "DONE")
            save_to_file(opt, id)
            return
        end
        current_time = time_ns()
        if current_time - last_save_time > UInt(60_000_000_000)
            save_to_file(opt, id)
            last_save_time = current_time
        end
        # if opt.last_step_type[] == DZOptimization.GradientDescentStep
        #     print_table_row(opt, "GRAD")
        #     last_print_time = current_time
        # elseif TERM && (current_time - last_print_time > UInt(100_000_000))
        #     rmk_table_row(opt, "BFGS")
        #     last_print_time = current_time
        # end
    end
end


## clean
function run!(opt, id::RKTKID, duration_ns::UInt) where {T <: Real}
    """
    Run the optimization in-place until convergence or until the specified duration has elapsed.

    Arguments:
    - `opt`: the optimizer to run.
    - `id::RKTKID`: an identifier for the optimization problem.
    - `duration_ns::UInt`: the maximum duration of the optimization process, in nanoseconds.

    Returns:
    - A boolean value indicating whether the optimization process has converged.
    """

    println("cleaning -- running")

    folder_name = "RKTK_order_$(id.order)_num_stages$(id.num_stages)_precisionFloat$(precision(BigFloat))_clean"
    
    # create folder if it does not exist
    if !isdir(folder_name)
        mkdir(folder_name)
    end

    start_time = last_save_time = time_ns()
    while true
        step!(opt)
        current_time = time_ns()
        if opt.has_converged[] || (current_time - start_time > duration_ns)
            save_to_file(opt, id, folder_name)
            return opt.has_converged[]
        end
        if current_time - last_save_time > UInt(60_000_000_000)
            save_to_file(opt, id, folder_name)
            last_save_time = current_time
        end
    end
end

################################################################################

function search(::Type{T}, id::RKTKID) where {T <: Real}
    """
    search(::Type{T}, id::RKTKID) where {T <: Real}

    Runs a search algorithm to find a Runge-Kutta method of the specified order and number of stages
    for the given `id`, using the specified floating-point precision `T`.

    # Arguments
    - `T`: The type of floating-point numbers to use.
    - `id`: The ID of the Runge-Kutta method to search for.
    """

    setprecision(approx_precision(T))
    num_vars = div(id.num_stages * (id.num_stages + 1), 2)

    ## Create an instance of an RKOC optimizer with the specified parameters
    optimizer = rkoc_optimizer(T, id.order, id.num_stages,
        rand(BigFloat, num_vars), 0)

    # # precision_str = string(T)
    # # println("T has type $(precision_str)")

    say("Running $T search $id.\n")
    run!(optimizer, id)
    say("\nCompleted $T search $id.\n")
end

function refine(::Type{T}, id::RKTKID, filename::String) where {T <: Real}
    """
    Runs a refinement on the optimization progress saved in a file with the given ID and filename
    using the given floating-point number type.
    
    Args:
        T (Type{T}): The type of floating-point numbers to use in the optimization.
        id (RKTKID): The ID of the file to refine.
        filename (str): The filename of the file to refine.
    
    Returns:
        None.
    """   
    
    setprecision(approx_precision(T))
    say("Running ", T, " refinement $id.\n")
    optimizer, header = rkoc_optimizer(T, id, filename)
    
    if precision(BigFloat) < parse(Int, header[2])
        say("WARNING: Refining at lower precision than source file.\n")
    end

    starting_iteration = optimizer.iteration_count[]
    run!(optimizer, id)
    ending_iteration = optimizer.iteration_count[]
    
    if ending_iteration > starting_iteration
        say("\nRepeating $T refinement $id.\n")
        refine(T, id, find_filename_by_id(".", id))
    else
        say("\nCompleted $T refinement $id.\n")
    end
end

function clean(::Type{T}) where {T <: Real}
    setprecision(approx_precision(T))
    optimizers = Tuple{Int,RKTKID,Any}[]
    for filename in readdir()
        if match(RKTKID_REGEX, filename) !== nothing
            id = find_rktkid(filename)
            optimizer, header = rkoc_optimizer(T, id, filename)
            if precision(BigFloat) < parse(Int, header[2])
                say("ERROR: Cleaning at lower precision than source file \"",
                    filename, "\".")
                exit()
            end
            push!(optimizers,
                (log_score(optimizer.current_objective_value[]), id, optimizer))
        end
    end
    say("Found ", length(optimizers), " RKTK files.")
    while true
        num_optimizers = length(optimizers)
        sort!(optimizers, by=(t -> t[1]), rev=true)
        completed = zeros(Bool, num_optimizers)
        @threads for i = 1 : num_optimizers
            _, id, optimizer = optimizers[i]
            old_score = rktk_score_str(optimizer)
            start_iter = optimizer.iteration_count[]
            completed[i] = run!(optimizer, id, UInt(10_000_000_000))
            stop_iter = optimizer.iteration_count[]
            new_score = rktk_score_str(optimizer)
            say(ifelse(completed[i], "    Cleaned ", "    Working "),
                id, " (", stop_iter - start_iter, " iterations: ",
                old_score, " => ", new_score, ") on thread ", threadid(), ".")
        end
        next_optimizers = Tuple{Int,RKTKID,Any}[]
        for i = 1 : length(optimizers)
            if !completed[i]
                _, id, optimizer = optimizers[i]
                push!(next_optimizers,
                    (log_score(optimizer.current_objective_value[]), id, optimizer))
            end
        end
        if length(next_optimizers) == 0
            say("All RKTK files cleaned!")
            break
        end
        optimizers = next_optimizers
        say(length(optimizers), " RKTK files remaining.")
    end
end


function clean_folder(folder_path::AbstractString, ::Type{T}) where {T <: Real}
    """
    clean_folder(folder_path::AbstractString, T)
    
    Recursively cleans all files with a valid RKTKID filename in the specified folder and its subfolders,
    using the given precision type T.
    
    Arguments:
    
        folder_path::AbstractString: the path of the folder to be cleaned.
        T: the precision type to be used for the cleaning.
    
    Returns: nothing.
    """
   
    setprecision(approx_precision(T))
    optimizers = Tuple{Int,RKTKID,Any}[]
    for filename in readdir(folder_path)
        if match(RKTKID_REGEX, filename) !== nothing
            file_path = joinpath(folder_path, filename)
            id = find_rktkid(filename)

            optimizer, header = rkoc_optimizer(T, id, file_path)
            if precision(BigFloat) < parse(Int, header[2])
                say("ERROR: Cleaning at lower precision than source file \"",
                    filename, "\".")
                exit()
            end
            push!(optimizers,
                (log_score(optimizer.current_objective_value[]), id, optimizer))
        end
    end
    say("Found ", length(optimizers), " RKTK files.")
    while true
        num_optimizers = length(optimizers)
        sort!(optimizers, by=(t -> t[1]), rev=true)
        completed = zeros(Bool, num_optimizers)
        @threads for i = 1 : num_optimizers
            _, id, optimizer = optimizers[i]
            old_score = rktk_score_str(optimizer)
            start_iter = optimizer.iteration_count[]
            completed[i] = run!(optimizer, id, UInt(10_000_000_000))
            stop_iter = optimizer.iteration_count[]
            new_score = rktk_score_str(optimizer)
            say(ifelse(completed[i], "    Cleaned ", "    Working "),
                id, " (", stop_iter - start_iter, " iterations: ",
                old_score, " => ", new_score, ") on thread ", threadid(), ".")
        end
        next_optimizers = Tuple{Int,RKTKID,Any}[]
        for i = 1 : length(optimizers)
            if !completed[i]
                _, id, optimizer = optimizers[i]
                push!(next_optimizers,
                    (log_score(optimizer.current_objective_value[]), id, optimizer))
            end
        end
        if length(next_optimizers) == 0
            say("All RKTK files cleaned!")
            break
        end
        optimizers = next_optimizers
        say(length(optimizers), " RKTK files remaining.")
    end
end



function benchmark(::Type{T}, order::Int, num_stages::Int,
        benchmark_secs) where {T <: Real}
    setprecision(approx_precision(T))
    num_vars = div(num_stages * (num_stages + 1), 2)
    x_init = [BigFloat(i) / num_vars for i = 1 : num_vars]
    construction_ns = time_ns()
    opt = rkoc_optimizer(T, order, num_stages, x_init, 0)
    start_ns = time_ns()
    benchmark_ns = round(typeof(start_ns), benchmark_secs * 1_000_000_000)
    terminated_early = false
    while time_ns() - start_ns < benchmark_ns
        step!(opt)
        if opt.has_converged[]
            terminated_early = true
            break
        end
    end
    Int(start_ns - construction_ns), opt.iteration_count[], terminated_early
end

function benchmark(::Type{T}, order::Int, num_stages::Int,
        benchmark_secs, num_trials::Int) where {T <: Real}
    construction_secs = Float64[]
    iteration_counts = Int[]
    success = true
    for _ = 1 : num_trials
        construction_ns, iteration_count, terminated_early =
            benchmark(T, order, num_stages, benchmark_secs / num_trials)
        push!(construction_secs, construction_ns / 1_000_000_000)
        push!(iteration_counts, iteration_count)
        if terminated_early
            success = false
            break
        end
    end
    if success
        say(rpad("$T: ", 16, ' '),
            shortstr(mean(iteration_counts)), " ± ",
            shortstr(std(iteration_counts)))
    else
        say(rpad("$T: ", 16, ' '), "Search terminated too early")
    end
end

################################################################################

function get_order(n::Int)
    """
    get_order(n::Int)
    
    Return an integer representing the order of the Runge-Kutta method to be used for RKTK.
    Arguments
    
        n::Int: an integer representing the position of the order parameter in the command line arguments (ARGS).
    
    Returns
    
        An integer representing the order of the Runge-Kutta method.
    
    Errors
    
        Throws an error and exits the program if the n parameter is not a valid integer between 1 and 20.
    """

    result = tryparse(Int, ARGS[n])
    if (result === nothing) || (result < 1) || (result > 20)
        say("ERROR: Parameter $n (\"$(ARGS[n])\") must be ",
            "an integer between 1 and 20.")
        exit()
    end
    result
end

function get_num_stages(n::Int)
    """
    Parses and validates the stage parameter passed as the nth argument.
    Must be an integer between 1 and 99.

    Args:
    n (int): The position of the stage parameter in the command line arguments.

    Returns:
        int: The validated number of stages.
    """

    result = tryparse(Int, ARGS[n])
    if (result === nothing) || (result < 1) || (result > 99)
        say("ERROR: Stage parameter $n (\"$(ARGS[n])\") must be ",
            "an integer between 1 and 99.")
        exit()
    end
    result
end

function main()
    """
    main()

    The main entry point of the RKToolbox program. Parses command-line arguments and dispatches to subcommands.
    """

    if (length(ARGS) == 0) || ("-h" in ARGS) || ("--help" in ARGS) let
        print_help()

    end elseif uppercase(ARGS[1]) == "SEARCH" let
        # If the first argument is "SEARCH", run an infinite search loop using the
        # specified precision, order, and number of stages.
        order, num_stages = get_order(2), get_num_stages(3)
        prec = parse(Int, ARGS[4])
        while true
            search(precision_type(prec), RKTKID(order, num_stages, uuid4()))
            
            # break
        end

    ## This was originally commented - J.P.Curbelo
    # end elseif uppercase(ARGS[1]) == "MULTISEARCH" let
    #     order, num_stages = get_order(2), get_num_stages(3)
    #     prec = parse(Int, ARGS[4])
    #     multisearch(precision_type(prec), order, num_stages)

    end elseif uppercase(ARGS[1]) == "REFINE" let
        id = find_rktkid(ARGS[2])
        if id === nothing
            say("ERROR: Invalid RKTK ID ", ARGS[2], ".")
            say("RKTK IDs have the form ",
                "RKTK-XXYY-ZZZZZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZZZZZZZZZ.\n")
            exit()
        end

        filename = find_filename_by_id(".", id)   #"."
        if filename === nothing
            say("ERRORRRRR: No file exists with RKTK ID $id.\n")
            exit()
        end
        prec = parse(Int, ARGS[3])
        refine(precision_type(prec), id, filename)

    # # end elseif uppercase(ARGS[1]) == "CLEAN" let
    # #     prec = parse(Int, ARGS[2])
    # #     clean(precision_type(prec))

    end elseif uppercase(ARGS[1]) == "CLEAN" let
        prec = parse(Int, ARGS[2])
        if length(ARGS) == 3 
            clean_folder(ARGS[3], precision_type(prec))
        else
            clean(precision_type(prec))
        end

    end elseif uppercase(ARGS[1]) == "BENCHMARK" let
        order, num_stages = get_order(2), get_num_stages(3)
        benchmark_secs = parse(Float64, ARGS[4])
        num_trials = parse(Int, ARGS[5])
        for T in (Float32, Float64, Float64x2, Float64x3, Float64x4,
                    Float64x5, Float64x6, Float64x7, Float64x8)
            benchmark(T, order, num_stages, benchmark_secs, num_trials)
        end
        for T in (Float32, Float64, Float64x2, Float64x3, Float64x4,
                    Float64x5, Float64x6, Float64x7, Float64x8)
            setprecision(approx_precision(T))
            benchmark(BigFloat, order, num_stages, benchmark_secs, num_trials)
        end
        say()

    end else let
        say("ERROR: Unrecognized <command> option \"", ARGS[1], "\".\n")
        print_help()

    end end
end

main()
