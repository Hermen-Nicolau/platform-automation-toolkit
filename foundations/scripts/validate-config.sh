#!/bin/bash -e

######DONE##### Select function to pick one of the two IAAS and store it in the variable iaas
function select_iaas () {

  declare -a IAAS_SELECT=(aws vsphere)


  for index in ${!IAAS_SELECT[@]}; do
    printf "%4d: %s\n" $index ${IAAS_SELECT[$index]}
  done

  read -p 'Choose a iaas: ' iaas_input

  iaas=${IAAS_SELECT[$iaas_input]}

  if [[ ${iaas} == "aws" || ${iaas} == "vsphere" ]]; then
    echo "You chose IAAS: ${IAAS_SELECT[$iaas_input]}"
  else
    echo "Unsupported iaas"
    exit 1    
  fi
  
}



function select_foundation () {
  select_iaas
  
  #hardcoded now - in the future we will read it from the git file structure
  AWS_FOUNDATIONS=(use1-lab use1-dev1 use2-dev1 usw2-dev use1-cde1 use2-cde1) 
  VSPHERE_FOUNDATIONS=(dal-dev2 phx-dev2 phx-cde2 dal-cde2)

  if [[ ${iaas} == "aws" ]]; then
    printf "The available foundations for ${iaas} are: \n"
    for index in ${!AWS_FOUNDATIONS[@]}; do
      printf "%4d: %s\n" $index ${AWS_FOUNDATIONS[$index]}
    done
    FOUNDATIONS=("${AWS_FOUNDATIONS[@]}")

  elif [[ ${iaas} == "vsphere" ]]; then
    printf "The available foundations for ${IAAS} are: \n"
    for index in ${!VSPHERE_FOUNDATIONS[@]}; do
      printf "%4d: %s\n" $index ${VSPHERE_FOUNDATIONS[$index]}
    done
    FOUNDATIONS=("${VSPHERE_FOUNDATIONS[@]}")

  fi

  read -p 'Choose a foundation: ' foundation
  echo "The foundation selected is: ${FOUNDATIONS[$foundation]}"
  environment_name=${FOUNDATIONS[$foundation]}
  
  if [[ ${environment_name} == "" ]]; then
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
  PRODUCT_LIST=( $(awk -F '-version' '{print $1}' ../$iaas/$environment_name/versions/version.yml | grep -v opsman -v | grep -v stemcell ))
  # Display the products
  echo "Available products:"
  for index in "${!PRODUCT_LIST[@]}"; do
    printf "%4d: %s\n" "$index" "${PRODUCT_LIST[$index]}"
  done

  read -p 'Choose a product: ' product_input
  echo "The selected product is: ${PRODUCT_LIST[$product_input]}"
  product=${PRODUCT_LIST[$product_input]}

  if [[ ${product} == "" ]]; then
    echo "Wrong selection !!! No such product found"
    exit 1
  fi

}

select_product
# iaas=$1
# environment_name=$2
# product=$3

echo "Validating configuration for product $product"

deploy_type="tile"
if [ "${product}" == "os-conf" ]; then
  deploy_type="runtime-config"
fi
if [ "${product}" == "clamav" ]; then
  deploy_type="runtime-config"
fi

vars_files_args=("")
if [ -f "../${iaas}/${environment_name}/config/defaults/${product}.yml" ]; then
  vars_files_args+=("--vars-file ../${iaas}/${environment_name}/config/defaults/${product}.yml")
fi

if [[ "${deploy_type}" == "runtime-config" ]]; then
  vars_files_args+=("--vars-file ../${iaas}/${INITIAL_FOUNDATION}/versions/${product}.yml")
fi

if [ -f "../${iaas}/common/${product}.yml" ]; then
  vars_files_args+=("--vars-file ../${iaas}/common/${product}.yml")
fi

if [ -f "../${iaas}/${environment_name}/config/vars/${product}.yml" ]; then
  vars_files_args+=("--vars-file ../${iaas}/${environment_name}/config/vars/${product}.yml")
fi

if [ -f "../${iaas}/${environment_name}/config/secrets/${product}.yml" ]; then
  vars_files_args+=("--vars-file ../${iaas}/${environment_name}/config/secrets/${product}.yml")
fi

if [ "${deploy_type}" == "tile" ]; then
  bosh int --var-errs-unused ../${iaas}/${environment_name}/config/templates/${product}.yml ${vars_files_args[@]} > /dev/null
fi

bosh int --var-errs ../${iaas}/${environment_name}/config/templates/${product}.yml ${vars_files_args[@]} > /dev/null
echo  "Validation script completed."