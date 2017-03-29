########################################################################
# Setup Ebits/HPC for the RWTH-Aachen cluster
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Contact: attila.gabor87@gmail.com
########################################################################


##Finding out the path
ebitsDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


usage()
{
cat << EOF

This program comes with ABSOLUTELY NO WARRANTY; for details visit http://www.gnu.org/licenses/gpl.html. This is free software, and you are welcome to redistribute it under certain conditions; visit http://www.gnu.org/licenses/gpl.html for details.

OPTIONS:
   -u      TIM number (required)

EOF
}


# ========================= 
# Process Input parameters
# =========================


#Defaults -- Change those if you want
sshDir=~/.ssh 


#Defaults -- Do not change
#tempdir=/tmp
export LANG=C #locale defaults
export LC_ALL=C #locale defaults

TODO=""


while getopts "u:" OPTION
do
	case $OPTION in
	u) tim=$OPTARG
    ;;
	?)
	usage
	exit
	;;
	esac
done

echo $tim
echo "tim not found"
if [ -z $tim ]; then
    printf "Error: TIM number not found\nExiting!\n";
    usage
    exit 1;
fi


#=======================> DONE!

# ========================= 
# Setup local machine
# =========================

printf "\n\n============================================\nSetup started!\n============================================\n\n"

printf "ebits directory:\n"$ebitsDIR"\n"
cd $ebitsDIR
printf "\n>>> Switch to ssh+lsf branch:\n"
git checkout ssh+lsf


printf "\n>>> Setting up your .Rprofile:\n"
if [[ ! -f ~/.Rprofile ]]; then
	echo ".Rprofile does not exist, we create at: ~/.Rprofile"
	echo "options(import.path = \""$ebitsDIR"\")" >> ~/.Rprofile
else
	echo ".Rprofile is detected, we added script to ~/.Rprofile. Please check for consistency."
	TODO+=".Rprofile is detected, we added script to ~/.Rprofile. Please check for consistency."
	echo "options(import.path = \""$ebitsDIR"\")" >> ~/.Rprofile
fi

printf "\n>>> Setting up R packages:\n"
RSuccess=$(Rscript ./setup_rdependency.R)

if [[ $RSuccess == TRUE ]]; then
	printf "Installation of R packages went OK.\n"
else
	printf "\nError is detected durng the installation of the packages.\nPlease try to install manually the missing packages.\n"
	exit 1
fi

printf "\n>>> Setting up SSH key for the cluster.\n"
if [[ -d $sshDir ]]; then
	printf $sshDir" directory exists\n"
else
	mkdir $sshDir	
fi

ssh-keygen -t rsa -b 2048 -f $sshDir/id_rsa
chmod 700 $sshDir && chmod 600 $sshDir/*

sshDirCluster=/home/$tim/.ssh

# Copy the public key to the cluster:
catCluster='mkdir '$sshDirCluster' && cat - >> '$sshDirCluster'/authorized_keys'
echo $catCluster
cat $sshDir/id_rsa.pub | ssh -l $tim cluster.rz.rwth-aachen.de $catCluster

# setup ssh config
printf "\n>>> Setting up short name for connecting to the RWTH-cluster at cluster.rz.rwth-aachen.de\n"

echo "Host rwth_cluster" >> $sshDir/config
echo "HostName cluster.rz.rwth-aachen.de" >> $sshDir/config
echo "HOST "$tim >> $sshDir/config

printf "instead of 'ssh -l TIM cluster.rz.rwth-aachen.de' you can use 'ssh rwth_aachen' from now on.\n"
#================================> DONE!




if [[ -z $TODO ]]; then
	printf "\n\n(!!!) We detected some warnings during the setup. Please check the following list:\n"
	printf $TODO"\n"
fi



