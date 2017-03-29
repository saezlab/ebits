library(modules)
hpc = import('hpc')

## SIMPLE TEST --------------------------------------------------------

res = hpc$Q(function(x) x*2, x=1:5, n_jobs=5, template="SSH_LSF_RWTH")

## CellNOptR TEST --------------------------------------------------------
library(CellNOptR)



prepareWorker <- function(x){
	library(abcto)
	install.packages("CellNOptR",repos = "http://cran.us.r-project.org")
	return("CellNOptR" %in% installed.packages()	)	
}
resCNO = hpc$Q(prepareWorker, x=1, n_jobs=1, template="SSH_LSF_RWTH")






prepareWorker <- function(x){
	is.installed = ("abctools" %in% installed.packages())
	if(is.installed)
		return("abctools is already installed.")
	else
		install.packages("abctools",repos = "http://cran.us.r-project.org")
	
	is.installed = ("abctools" %in% installed.packages())
	if(is.installed)
		return('we installed abctools.')
	else
		return('abctools were not installed')
}
resCNO = hpc$Q(prepareWorker, x=1, n_jobs=1, template="SSH_LSF_RWTH")







data(CNOlistToy,package="CellNOptR")
data(ToyModel,package="CellNOptR")

pknmodel = ToyModel
cnolist = CNOlist(CNOlistToy)
model = preprocessing(cnolist, pknmodel)


# make sure CellNOptR is installed on the cluster
worker <- function(rep,cnolist,model){
	library(CellNOptR)
	
	results = gaBinaryT1(cnolist, model, verbose=TRUE)
	results$rep = rep

	return(results)	
}

resCNO = hpc$Q(worker, const = list(cnolist=cnolist,model=model),rep=1:5, n_jobs=5, template="SSH_LSF_RWTH")
