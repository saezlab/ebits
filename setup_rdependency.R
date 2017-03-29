req1 = c('devtools','BatchJobs','gtools','plyr','dplyr','abind','reshape2','xlsx','rzmq','infuser','pryr')

# implicit dependencies: stringr, magrittr
new = req1[!(req1 %in% installed.packages()[,"Package"])]
if(length(new)) install.packages(new,repos = "http://cran.us.r-project.org")

if(!('ulimit' %in% installed.packages())) devtools::install_github("krlmlr/ulimit")
if(!('modules' %in% installed.packages())) {
	devtools::install_github('klmr/modules')
	devtools::install_github('klutometis/roxygen@v5.0.1')
}

# CHECK IF ALL PACKAGES ARE INSTALLED:
allReq = c('devtools','BatchJobs','gtools','plyr','dplyr','abind','reshape2','xlsx','rzmq','infuser','pryr','ulimit','modules', 'roxygen2')
failed = allReq[!(allReq %in% installed.packages()[,"Package"])]


if(length(failed)>0){
	print(paste("packages not installed:", paste(failed,sep=', ')))
	cat(FALSE)
}else
	cat(TRUE)