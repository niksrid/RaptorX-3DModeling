#!/bin/bash

DeepModelFile=$DL4DistancePredHome/params/ModelFile4PairwisePred.txt
DefaultModel4FM=EC47C37C19CL99S35V2020MidModels
DefaultModel4HHP=HHEC47C37C19CL99S35PDB70Models
DefaultModel4NDT=NDTEC47C37C19CL99S35BC40Models

ModelName=""

GPU=-1
ResultDir=`pwd`

MSAmethod=4
UseMetaGenomeData=true

tplStr=""
aliStr=""

alignmentType=0

function Usage 
{
	echo $0 "[ -f DeepModelFile | -m ModelName | -d ResultDir | -g gpu | -s MSAmethod | -M ] proteinListFile metaFolder"
	echo Or $0 "[ -f DeepModelFile | -m ModelName | -d ResultDir | -g gpu | -s MSAmethod | -M | -T alignmentType ] proteinListFile metaFolder aliFolders tplFolder"
        echo "  This script predicts contact/distance/orientation for multiple proteins"
	echo "	proteinListFile: a file for a list of proteins, each in one row"
        echo "	metaFolder: a folder containing some subfolders XXX_OUT, which in turn shall contain a subfolder XXX_contact (e.g., T0955_OUT/T0955_contact/)"
	echo "		Each XXX_contact/ shall contain some subfolders such as feat_XXX_YYY where YYY represents an MSA generation method, e.g., uce3, ure3_meta"
	echo "	-s: indicates which MSAs to be used, 0 for hhblits, 1 for jackhmmer, 2 for both, 3 for user-provided MSA and 4 for all three, default $MSAmethod"
	echo "	-M: if specified, do not use meta genome data, default use it when available"
	echo " "
	echo "	aliFolders: optional, specify one or multiple folders that contain query-template alignments. The folders shall be saparated by ; without whitespace"
        echo "		One alignment file shall be in FASTA format and have name proteinName-*.fasta"
	echo "		Two different alignment files shall have differnt names even if they are in different folders"
        echo "	tplFolder: optional, specify a folder containing template files. One template file shall end with .tpl.pkl and be generated by Common/MSA2TPL.sh"
	echo "	-T: indicate how query-template alignments are generated: 1 for alignments generated by HHpred and 2 for alignments generated by RaptorX threading"
        echo "		This option will be used only if both aliFolders and tplFolder are present"
	echo " "
	echo "	-f: a file containing a set of deep model names, default $DeepModelFile"
	echo "	-m: a model name defined in DeepModelFile representing a set of deep learning models. Below is the default setting:"
        echo "		When aliFolders are not used, $DefaultModel4FM will be used. Otherwise, when alignmentType is not set, $DefaultModel4HHP will be used"
        echo "		When aliFolders are used, if alignmentType=2, $DefaultModel4NDT will be used; otherwise $DefaultModel4HHP will be used"
        echo "	-d: the folder for result saving, default current work directory "
        echo "	-g: -1 (default), 0-3; if -1, select a GPU with maximum amount of free memory"
	echo "		Users shall make sure that at least one GPU has enough memory for the prediction job. Otherwise it may crash itself or other jobs"
}

while getopts ":f:m:d:g:s:T:M" opt; do
        case ${opt} in
                f )
                  DeepModelFile=`readlink -f $OPTARG`
                  ;;
                m )
                  ModelName=$OPTARG
                  ;;
                d )
                  ResultDir=$OPTARG
                  ;;
                g )
                  GPU=$OPTARG
                  ;;
		T )
		  alignmentType=$OPTARG
		  ;;
		M )
		  UseMetaGenomeData=false
		  ;;
		s )
		  MSAmethod=$OPTARG
		  ;;
                \? )
                  echo "Invalid Option: -$OPTARG" 1>&2
                  exit 1
                  ;;
                : )
                  echo "Invalid Option: -$OPTARG requires an argument" 1>&2
                  exit 1
                  ;;
        esac
done
shift $((OPTIND -1))

if [ $# -ne 2 -a $# -ne 4 ]; then
        Usage
        exit 1
fi

proteinListFile=$1
if [ ! -f $proteinListFile ]; then
	echo "ERROR: invalid file for protein list: $proteinListFile "
	exit 1
fi

MetaDir=$2
if [ ! -d $MetaDir ]; then
	echo "ERROR: invalid meta folder for protein features: $MetaDir"
	exit 1
fi

if [ $# -eq 4 ]; then
	aliStr=$3
	tplStr=$4
fi

if [ ! -f $DeepModelFile ]; then
        echo "ERROR: invalid file for deep model path information: $DeepModelFile"
        exit 1
fi

cmd=`readlink -f $0`
cmdDir=`dirname $cmd`
parentDir=`dirname $cmdDir`

tmpdir=$(mktemp -d -t RXFeature4Proteins-XXXXXXXXXX)
if $UseMetaGenomeData; then
	$cmdDir/LinkDistFeatures4MultiProteins.sh -d $tmpdir -s $MSAmethod $proteinListFile $MetaDir
	if [ $? -ne 0 ]; then
		echo "ERROR: failed to run $cmdDir/LinkDistFeatures4MultiProteins.sh -d $tmpdir $proteinListFile $MetaDir"
		exit 1
	fi
else
	$cmdDir/LinkDistFeatures4MultiProteins.sh -d $tmpdir -s $MSAmethod -M $proteinListFile $MetaDir
	if [ $? -ne 0 ]; then
		echo "ERROR: failed to run $cmdDir/LinkDistFeatures4MultiProteins.sh -d $tmpdir -M $proteinListFile $MetaDir"
		exit 1
	fi
fi

featDirs=`ls -d $tmpdir/features-*`

if [ ! -d $ResultDir ]; then
	mkdir -p $ResultDir
fi

options=" -f $DeepModelFile -d $ResultDir -g $GPU "
if [ ! -z "$ModelName" ]; then
	options=$options" -m $ModelName "
fi

if [ $# -eq 4 ]; then
	if [ $alignmentType -ne 0 ]; then
		options=$options" -T $alignmentType "
	fi
	options=$options" -a $aliStr -t $tplStr "
fi

echo Running $cmdDir/PredictPairRelation4Inputs.sh $options $proteinListFile $featDirs
$cmdDir/PredictPairRelation4Inputs.sh $options $proteinListFile $featDirs
if [ $? -ne 0 ]; then
	echo "ERROR: failed to run $cmdDir/PredictPairRelation4Inputs.sh $options $proteinListFile $featDirs"
	exit 1
fi

rm -rf $tmpdir
