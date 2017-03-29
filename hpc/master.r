# Rationale
#  This script uses rzmq to run function calls as LSF jobs.
#  The function supplied *MUST* be self-sufficient, i.e. load libraries and scripts.
#
# Usage
#  * Q(...)     : general queuing function
#
# Examples
#  > s = function(x) x
#  > Q(s, x=c(1:3), n_jobs=1)
#  returns list(1,2,3)
#
#  > t = function(x) sum(x)
#  > a = matrix(3:6, nrow=2)
#  > Q(t, a, n_jobs=1)
#  splits a by columns, sums each column, and returns list(7, 11)
#
# TODO list
#  * rerun failed jobs?
.p = import_('./process_args')

# Check that all the required packags (master and worker) are installed
.req_pkg = c("rzmq", "infuser", "ulimit")
.pkg_missing = setdiff(.req_pkg, rownames(installed.packages()))
if (length(.pkg_missing))
    stop("The following packages need to be installed: ", paste(.pkg_missing, sep=", "))

if (grepl("^0\\.[0-8]", packageVersion("modules")))
    stop("Needs modules >= 0.9; see: https://github.com/klmr/modules/issues/66")

#' Function to queue calls
#'
#' @param fun             A function to call
#' @param ...             Objects to be iterated in each function call
#' @param const           A list of constant arguments passed to each function call
#' @param expand_grid     Use all combinations of arguments in `...`
#' @param seed            A seed to set for each function call
#' @param memory          The amount of Mb to request from LSF; default: 1 Gb
#' @param time_req        Required CPU time in mins from the cluster. Jobs are killed after. 
#' @param n_jobs          The number of LSF jobs to submit
#' @param job_size        The number of function calls per job; if n_jobs is given,
#'                        this will have priority
#' @param split_array_by  The dimension number to split any arrays in `...`; default: last
#' @param fail_on_error   If an error occurs on the workers, continue or fail?
#' @param log_worker      Write a log file for each worker
#' @param wait_time       Time to wait between messages; set 0 for short cals
#'                        defaults to 1/sqrt(number_of_functon_calls)
#' @param template        Template file to use; will be "template_<template>.r" in this dir
#' @return                A list of whatever `fun` returned
Q = function(fun, ..., const=list(), expand_grid=FALSE, seed=128965,
        memory=4096, time_req=60, n_jobs=NULL, job_size=NULL, split_array_by=NA,
        fail_on_error=TRUE, log_worker=FALSE, wait_time=NA, template="LSF") {

    qsys = import_(paste0('./template_', template))
    stopifnot(c("submit_job", "cleanup") %in% ls(qsys))

    if (is.null(n_jobs) && is.null(job_size))
        stop("n_jobs or job_size is required")
    if (memory < 500)
        stop("Worker needs about 230 MB overhead, set memory>=500")

    fun = match.fun(fun)
    job_data = .p$process_args(fun, iter=list(...), const=const,
                               expand_grid=expand_grid,
                               split_array_by=split_array_by)
    names(job_data) = 1:length(job_data)

    if (is.null(n_jobs))
        n_jobs = ceiling(length(job_data) / job_size)

    on.exit(qsys$cleanup())
    qsys$init()

    # do the submissions
    message("Submitting worker jobs ...")
    pb = txtProgressBar(min=0, max=n_jobs, style=3)
    for (j in 1:n_jobs) {
        qsys$submit_job(memory=memory, log_worker=log_worker, time_req=time_req)
        setTxtProgressBar(pb, j)
    }
    close(pb)

    job_result = rep(list(NULL), length(job_data))
    submit_index = 1
    jobs_running = list()
    workers_running = list()
    worker_stats = list()
    if (is.na(wait_time))
        wait_time = ifelse(length(job_data) < 5e5, 1/sqrt(length(job_data)), 0)

    message("Running calculations ...")
    pb = txtProgressBar(min=0, max=length(job_data), style=3)

    # exchanging messages between the master and workers works the following way:
    #  * we have submitted a job where we don't know when it will start up
    #  * it starts, sends is a message list(id=0) indicating it is ready
    #  * we send it the function definition and common data
    #    * we also send it the first data set to work on
    #  * when we get any id > 0, it is a result that we store
    #    * and send the next data set/index to work on
    #  * when computatons are complete, we send id=0 to the worker
    #    * it responds with id=-1 (and usage stats) and shuts down
    start_time = proc.time()
    while(submit_index <= length(job_data) || length(workers_running) > 0) {
        msg = qsys$receive_data()
        if (msg$id == 0) { # worker ready, send common data
            qsys$send_common_data(fun=fun, const=const, seed=seed)
            workers_running[[msg$worker_id]] = TRUE
        } else if (msg$id == -1) { # worker done, shutting down
            worker_stats[[msg$worker_id]] = msg$time
            workers_running[[msg$worker_id]] = NULL
        } else { # worker sending result
            jobs_running[[as.character(msg$id)]] = NULL
            job_result[[msg$id]] = msg$result
            setTxtProgressBar(pb, submit_index - length(jobs_running) - 1)
        }

        if (submit_index <= length(job_data)) { # send iterated data to worker
            qsys$send_job_data(id=submit_index, iter=as.list(job_data[[submit_index]]))
            jobs_running[[as.character(submit_index)]] = TRUE
            submit_index = submit_index + 1
        } else # send shutdown signal to worker
            qsys$send_job_data(id=0)

        Sys.sleep(wait_time)
    }

    rt = proc.time() - start_time
    close(pb)

    on.exit(NULL)

    failed = sapply(job_result, class) == "try-error"
    if (any(failed)) {
        warning(job_result[failed])
        if (fail_on_error)
            stop("errors occurred, stopping")
    }

    wt = Reduce(`+`, worker_stats) / length(worker_stats)
    message(sprintf("Master: [%.1fs %.1f%% CPU]; Worker average: [%.1f%% CPU]",
                    rt[[3]], 100*(rt[[1]]+rt[[2]])/rt[[3]],
                    100*(wt[[1]]+wt[[2]])/wt[[3]]))

    job_result
}

if (is.null(module_name())) {
    library(testthat)

    # test if memory limits raise and error instead of crashing r
    # note that the worker has about 225 MB overhead
    fx = function(x) {
        test = rep(1,x)
        TRUE
    }
    re = Q(fx, (20:50)*1e6, memory=500, n_jobs=1, fail_on_error=FALSE)
    expect_equal(unique(sapply(re, class)),
                 c("logical", "try-error"))
}
