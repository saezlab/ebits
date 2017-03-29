library(modules)
hpc = import('hpc')

## SIMPLE TEST --------------------------------------------------------

res = hpc$Q(function(x) x*2, x=1:5, n_jobs=5, template="SSH_LSF_RWTH")

## CellNOptR TEST --------------------------------------------------------
library(CellNOptR)

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
