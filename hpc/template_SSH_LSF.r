rzmq = import_package_('rzmq')
infuser = import_package_('infuser')

#' A template string used to submit jobs
#template = "bsub -J {{ job_name}} -g {{ job_group || /rzmq }} -o {{ log_file | /dev/null }} -P research-rh6 -W 10080 -M {{ memory | 4096 }} -R \"rusage[mem={{ memory | 4096 }}]\" -R \"select[gpfs]\" R --no-save --no-restore --args {{ args }} < '{{ rscript }}'"
template = "bsub -J {{ job_name}} Rscript {{ rscript }} {{ args }}"

#' Number submitted jobs consecutively
job_num = 1

#' Job group that all jobs belong to
job_group = NULL

#' The rZMQ socket object
socket = NULL

#' An rzmq-compatible address to connect the worker to
master = NULL

#' The serialized common data
common_data = NULL

#' The ZerMQ context object
#'
#' Having this on the module level and not inside the init() function
#' is absolutely crucial, otherwise the object is garbage collected
#' at some point and everything breaks
zmq.context = NULL

#' Initialize the rZMQ context and bind the port
init = function() {
    # be sure our variables are set right to start out with
    assign("job_num", 1, envir=parent.env(environment()))
    assign("job_group", NULL, envir=parent.env(environment()))
    assign("socket", NULL, envir=parent.env(environment()))
    assign("master", NULL, envir=parent.env(environment()))
    assign("common_data", NULL, envir=parent.env(environment()))
    assign("zmq.context", rzmq$init.context(), envir=parent.env(environment()))

    # bind socket
    assign("socket", rzmq$init.socket(zmq.context, "ZMQ_REP"),
           envir=parent.env(environment()))

    sink('/dev/null')
    for (i in 1:100) {
        exec_socket = sample(6000:8000, size=1)
        port_found = rzmq$bind.socket(socket, paste0("tcp://*:", exec_socket))
        if (port_found)
            break
    }
    sink()

    if (!port_found)
        stop("Could not bind to port range (6000,8000) after 100 tries")

    assign("master", sprintf("tcp://%s:%i", Sys.info()[['nodename']], exec_socket),
           envir=parent.env(environment()))

    assign("ssh", pipe("ssh ebi", open="w"), envir=parent.env(environment()))
}

#' Submits one job to the queuing system
#'
#' @param memory      The amount of memory (megabytes) to request
#' @param log_worker  Create a log file for each worker
submit_job = function(memory, log_worker=FALSE) {
    if (is.null(master))
        stop("Need to call init() first")

    group_id = rev(strsplit(master, ":")[[1]])[1]
    job_name = paste0("rzmq", group_id, "-", job_num)

    values = list(
        job_name = job_name,
        job_group = paste("/rzmq", group_id, sep="/"),
        rscript = module_file("worker.r"),
        args = paste(job_name, master, memory)
    )

    assign("job_group", values$job_group, envir=parent.env(environment()))
    assign("job_num", job_num + 1, envir=parent.env(environment()))

#    if (log_worker)
        values$log_file = paste0("/dev/shm/", values$job_name, ".log")

    job_input = infuser$infuse(template, values)
    print(job_input)

    cat(job_input, "\n", file=ssh)
}

#' Read data from the socket
receive_data = function() {
	rzmq$receive.socket(socket)
}

#' Send the data common to all workers, only serialize once
send_common_data = function(...) {
	if (is.null(common_data))
		assign("common_data", serialize(list(...), NULL),
               envir=parent.env(environment()))

	rzmq$send.socket(socket, data=common_data, serialize=FALSE, send.more=TRUE)
}

#' Send interated data to one worker
send_job_data = function(...) {
	rzmq$send.socket(socket, data=list(...))
}

#' Will be called when exiting the `hpc` module's main loop, use to cleanup
cleanup = function() {
    cat(paste("bkill -g", job_group, "0"), ignore.stdout=FALSE, file=ssh)
    close(ssh)
}
