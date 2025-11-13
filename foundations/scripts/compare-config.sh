###### compare-config
#!/bin/bash -e
: ${PIVNET_TOKEN?"Need to set PIVNET_TOKEN"}


#Function to connect to pivnet 
function curlit() {

  curl_response=$(curl -s https://network.tanzu.vmware.com/$1 -X GET)
  if [ -z "$curl_response" ]; then
    fail "No response from curl: $1"
    exit 1
  else
    echo $curl_response
  fi
}

### needed if running the script and passing 2 arg
# if [ ! $# -eq 2 ]; then
#   echo "Must supply iaas and product name as arg"
#   exit 1
# fi

######DONE##### Select function to pick one of the two IAAS and store it in the variable iaas
function select_iaas () {

  declare -a IAAS_SELECT=(aws vsphere)


  for index in ${!IAAS_SELECT[@]}; do
    printf "%4d: %s\n" $index ${IAAS_SELECT[$index]}
  done

  read -p 'Choose a iaas: ' iaas

  IAAS=${IAAS_SELECT[$iaas]}

  if [[ ${IAAS} == "aws" || ${IAAS} == "vsphere" ]]; then
    echo "You chose IAAS: ${IAAS_SELECT[$iaas]}"
  else
    echo "Unsupported iaas"
    exit 1    
  fi
  
}

######DONE##### Select function to pick one of the foundations depending on the IAAS picked above - if statement and store it in the variable FOUNDATION_NAME

function select_foundation () {
  select_iaas
  
  #hardcoded now - in the future we will read it from the git file structure
  AWS_FOUNDATIONS=(use1-lab use1-dev1 use2-dev1 usw2-dev use1-cde1 use2-cde1) 
  VSPHERE_FOUNDATIONS=(dal-dev2 phx-dev2 phx-cde2 dal-cde2)

  if [[ ${IAAS} == "aws" ]]; then
    printf "The available foundations for ${IAAS} are: \n"
    for index in ${!AWS_FOUNDATIONS[@]}; do
      printf "%4d: %s\n" $index ${AWS_FOUNDATIONS[$index]}
    done
    FOUNDATIONS=("${AWS_FOUNDATIONS[@]}")

  elif [[ ${IAAS} == "vsphere" ]]; then
    printf "The available foundations for ${IAAS} are: \n"
    for index in ${!VSPHERE_FOUNDATIONS[@]}; do
      printf "%4d: %s\n" $index ${VSPHERE_FOUNDATIONS[$index]}
    done
    FOUNDATIONS=("${VSPHERE_FOUNDATIONS[@]}")
    
  # else
  #   echo "Unsupported foundation"
  #   exit 1
  fi
  
  read -p 'Choose a foundation: ' foundation
  echo "The foundation selected is: ${FOUNDATIONS[$foundation]}"
  FOUNDATION_NAME=${FOUNDATIONS[$foundation]}
  
  if [[ ${FOUNDATION_NAME} == "" ]]; then
    echo "Wrong selection !!! No such foundation found"
    exit 1
  fi
}

function select_product (){
  select_foundation
  #Extract the products from the versions.yml and store in array 
  ###TODO### Add the foundation variable to the PRODUCT_LIST var $FOUNDATION_NAME
#   PRODUCT_LIST=( $(awk -F '-version' '{print $1}' ../$IAAS/lab-1/versions/version.yml))
# removed opsman from the list since opsman configuration is not getting generated from the script
  PRODUCT_LIST=( $(awk -F '-version' '{print $1}' ../$IAAS/$FOUNDATION_NAME/versions/version.yml | grep -v opsman -v | grep -v stemcell ))
  # Display the products
  echo "Available products:"
  for index in "${!PRODUCT_LIST[@]}"; do
    printf "%4d: %s\n" "$index" "${PRODUCT_LIST[$index]}"
  done

  read -p 'Choose a product: ' product_input
  echo "The selected product is: ${PRODUCT_LIST[$product_input]}"
  PRODUCT=${PRODUCT_LIST[$product_input]}

  if [[ ${PRODUCT} == "" ]]; then
    echo "Wrong selection !!! No such product found"
    exit 1
  fi

}

### select product version from the availabe versions on pivnet
function select_product_version () {

  select_product
  VERSIONS=$(curlit api/v2/products/$PRODUCT/releases | jq -r '.releases[].version' | sort -V)
  # if [[ ${PRODUCT} == "p-concourse" ]]; then
  #   VERSIONS="7.9.1+LTS-T 7.11.2+LTS-T"
  # fi
  declare -a PRODUCT_VERSIONS=(${VERSIONS})

  for index in ${!PRODUCT_VERSIONS[@]}; do
    printf "%4d: %s\n" $index ${PRODUCT_VERSIONS[$index]}
  done

  read -p 'Choose the version that you are upgrading to: ' selected_version
  echo "You chose: ${PRODUCT_VERSIONS[$selected_version]}"
  version=${PRODUCT_VERSIONS[$selected_version]}
}

# function generate_config (){
# ---- Get version, glob, slug from version file
select_product_version

echo "Generating configuration for product $PRODUCT"
productfile="../${IAAS}/download-products/${PRODUCT}.yml"
versionfile="../${IAAS}/${FOUNDATION_NAME}/versions/version.yml"

if [ ! -f ${versionfile} ]; then
  echo "Must create ${versionfile}"
  exit 1
fi
current_version=$(bosh interpolate ${versionfile} --path=/${PRODUCT}-version)
glob=$(bosh interpolate ${productfile} --path=/pivnet-file-glob)
slug=$(bosh interpolate ${productfile} --path=/pivnet-product-slug)

### updating product glob for healthwatch
if [[ ${PRODUCT} == "p-healthwatch2" ]]; then
    glob=healthwatch-${version}*.pivotal
elif [[ ${PRODUCT} == "p-antivirus" ]]; then
    glob=${PRODUCT}-${version}*.pivotal
fi


# echo "product is : $PRODUCT"
# echo "version is : $version"
# echo "glob is : $glob"
# echo "slug is : $slug"


# ---- Execute om config-template 
tmpdir=outputs-compare-tile-config/${FOUNDATION_NAME}/${PRODUCT}
mkdir -p ${tmpdir}


## get clean git, 1. generate-config, validate-config, 
### old_config
### Tony's note: use om-staged-config  and then compare 

om config-template --output-directory=${tmpdir} --pivnet-api-token ${PIVNET_TOKEN} --pivnet-product-slug  ${slug} --product-version ${version} --pivnet-file-glob ${glob}
if [[ ${PRODUCT} == "vmware-nsx-t" ]]; then
  if [[ ${version} == "3.2.2.2" ]]; then
    version="3.2.1707xxx"
  elif [[ ${version} == "3.2.2" ]]; then
    version="3.2.16xxx"
  fi
fi

lts_substring="+LTS-T"
if [[ ${PRODUCT} == "cf" || ${PRODUCT} == "pas-windows" || ${PRODUCT} == "p-isolation-segment" ]]; then
  # don't really need the if check
  # this takes the ${version} and remove the template which is defined as anything ending in "+LTS-T"
  # if the result is empty (-z), then the ${version} did in fact end with that suffix
  # if [[ -z ${version##*$lts_substring} ]]; then
    # Remove the suffix defined in ${lts_substring} from ${version}
    version=${version%$lts_substring*}
  # fi
fi

wrkdir=$(find ${tmpdir}/${PRODUCT} -name "${version}*")
# echo "product is : ${tmpdir}"
# echo "product is : ${version}*"
# echo "the wrk dir is : ${wrkdir}"
# echo "product is : ${PRODUCT}"
if [ ! -f ${wrkdir}/product.yml ]; then
  echo "Something wrong with configuration as expecting ${wrkdir}/product.yml to exist. Please try running the script again incase of timeout"
  exit 1
fi

# ---- Create array of opsfiles to apply

if [ ! -f ../${IAAS}/${FOUNDATION_NAME}/opsfiles/${PRODUCT}-operations ]; then
  echo "Something wrong with configuration as expecting ${PRODUCT}-operations to exist. Please check if the opsfile  is present"
  exit 1
fi
# mkdir -p ../${IAAS}/opsfiles
ops_files="../${IAAS}/${FOUNDATION_NAME}/opsfiles/${PRODUCT}-operations"
touch ${ops_files}

ops_files_args=("")
custom_ops_files_args=("")

if [ -f ../${IAAS}/${FOUNDATION_NAME}/opsfiles/${PRODUCT}-custom.yml ]; then
    custom_ops_files_args+="-o ../${IAAS}/${FOUNDATION_NAME}/opsfiles/${PRODUCT}-custom.yml"
fi
# echo "first: ${ops_files_args[@]}"
while IFS= read -r var
do
  ops_files_args+=("-o ${wrkdir}/${var}")
#   echo "inside  ${ops_files_args[@]}" 
done < "$ops_files"

# echo "wrk dir is : ${wrkdir}"
# echo "ops file is $ops_files"


# echo "final:  ${ops_files_args[@]}"

# ---- Create template file from product.yml with applied opsfiles
mkdir -p outputs-compare-tile-config/${FOUNDATION_NAME}/generated-templates/
mkdir -p outputs-compare-tile-config/${FOUNDATION_NAME}/template-diff-output
# mkdir -p outputs-compare-tile-config/${FOUNDATION_NAME}/staged-config/

### tony's way
#om staged-config -e ../${IAAS}/${FOUNDATION_NAME}/env/env.yml -p ${PRODUCT} -r 

#mv ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}.yml ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}-current.yml

### generate new config
bosh int ${wrkdir}/product.yml ${ops_files_args[@]} ${custom_ops_files_args[@]} > outputs-compare-tile-config/${FOUNDATION_NAME}/generated-templates/${PRODUCT}-${version}.yml


rm -rf ${tmpdir}

echo "comparing new template for ${PRODUCT} current: ${current_version} with new: ${version}"

echo "showing the diffs and storing it as outputs-compare-tile-config/${FOUNDATION_NAME}/template-diff-output/${PRODUCT}-${current_version}-vs-${version}.yml"
#echo "Please run the below command see it on terminal"
#echo "diff -y ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}.yml outputs-compare-tile-config/${FOUNDATION_NAME}/generated-templates/${PRODUCT}-${version}.yml"

diff -y ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}.yml outputs-compare-tile-config/${FOUNDATION_NAME}/generated-templates/${PRODUCT}-${version}.yml & diff -u ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}.yml outputs-compare-tile-config/${FOUNDATION_NAME}/generated-templates/${PRODUCT}-${version}.yml > outputs-compare-tile-config/${FOUNDATION_NAME}/template-diff-output/${PRODUCT}-${current_version}-vs-${version}.yml

#### end of compare-config
