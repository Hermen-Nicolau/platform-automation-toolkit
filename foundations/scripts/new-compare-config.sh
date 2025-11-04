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

######DONE##### Select function to pick one of the two IAAS and store it in the variable iaas
function select_iaas () {

  declare -a IAAS_SELECT=(aws vsphere)

  for index in ${!IAAS_SELECT[@]}; do
    printf "%4d: %s\n" $index ${IAAS_SELECT[$index]}
  done

  read -p 'Choose a iaas: ' iaas
  echo "You chose: ${IAAS_SELECT[$iaas]}"
  IAAS=${IAAS_SELECT[$iaas]}
}

######DONE##### Select function to pick one of the foundations depending on the IAAS picked above - if statement and store it in the variable FOUNDATION_NAME


function select_foundation () {
  select_iaas
  
  #hardcoded now - in the future we will read it from the git file structure
  AWS_FOUNDATIONS=(use1-dev1 use2-dev1 usw2-dev use2-cde1) 
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
    
  else
    echo "Unsupported IAAS"
    exit 1
  fi

  read -p 'Choose a foundation: ' foundation
  echo "The foundation selected is: ${FOUNDATIONS[$foundation]}"
  FOUNDATION_NAME=${FOUNDATIONS[$foundation]}

}

#####DONE##### Read the versions.yml file and output the first column which are the products deployed


function select_product (){
  select_foundation
  #Extract the products from the versions.yml and store in array 
  ###TODO### Add the foundation variable to the PRODUCT_LIST var $FOUNDATION_NAME
  PRODUCT_LIST=( $(awk -F '-version' '{print $1}' ../$IAAS/lab-1/versions/version.yml))
  # Display the products
  echo "Available products:"
  for index in "${!PRODUCT_LIST[@]}"; do
    printf "%4d: %s\n" "$index" "${PRODUCT_LIST[$index]}"
  done

  read -p 'Choose a product: ' product_input
  echo "The selected product is: ${PRODUCT_LIST[$product_input]}"
  PRODUCT=${PRODUCT_LIST[$product_input]}

}

#####DONE#####Then new function to pick the new product version 


function select_product_version () {

  select_product
  echo $PRODUCT
  
  VERSIONS=$(curlit api/v2/products/$PRODUCT/releases | jq -r '.releases[].version' | sort -V)
  if [[ ${PRODUCT} == "p-concourse" ]]; then
    VERSIONS="7.9.1+LTS-T 7.11.2+LTS-T"
  fi
  declare -a PRODUCT_VERSIONS=(${VERSIONS})

  for index in ${!PRODUCT_VERSIONS[@]}; do
    printf "%4d: %s\n" $index ${PRODUCT_VERSIONS[$index]}
  done

  read -p 'Choose the version that you are upgrading to: ' version
  echo "You chose: ${PRODUCT_VERSIONS[$version]}"
  PRODUCT_VERSION=${PRODUCT_VERSIONS[$version]}
}

function select_glob (){
  select_product_version

  echo "PRODUCT: $PRODUCT"
  echo "PRODUCT_VERSION: $PRODUCT_VERSION"

  PRODUCT_METADATA=$(curlit api/v2/products/$PRODUCT/releases | jq -r '.releases[] | select(.version == '\"$PRODUCT_VERSION\"') | "\(.description)|\(.became_ga_at)|\(.release_date)|\(.end_of_support_date)|\(.release_notes_url)|\(.id)"')
  PRODUCT_ID=$(echo $PRODUCT_METADATA | cut -d '|' -f6)
  echo "PRODUCT_ID: $PRODUCT_ID"
  GLOBS=$(curlit api/v2/products/$PRODUCT/releases/$PRODUCT_ID/product_files | jq -r '.product_files[].aws_object_key' | cut -d '/' -f2)

  declare -a PRODUCT_GLOBS=(${GLOBS})

  for index in ${!PRODUCT_GLOBS[@]}; do
    printf "%4d: %s\n" $index ${PRODUCT_GLOBS[$index]}
  done

  read -p 'Choose a product file glob: ' glob
  echo "You chose: ${PRODUCT_GLOBS[$glob]}"
  PRODUCT_GLOB=${PRODUCT_GLOBS[$glob]}

}


function get_new_product_templates (){
  select_glob
  echo "PRODUCT: $PRODUCT"
  echo "PRODUCT_VERSION: $PRODUCT_VERSION"
  echo "PRODUCT_GLOB: $PRODUCT_GLOB"


  ## Show the diff directly into the terminal, not in a file 
  ## Best way to compare - talk with 

  echo "Generating configuration for new product $PRODUCT"
  # ---- Accept the Pivnet EULA
  echo "Accepting the Pivnet EULA"
  pivnet login --api-token=$PIVNET_TOKEN
  pivnet accept-eula -p ${PRODUCT} -r ${PRODUCT_VERSION}

  # ---- Execute om config-template 
  tmpdir=tile-configs/${PRODUCT}-config
  mkdir -p ${tmpdir}

  om config-template --output-directory=${tmpdir} --pivnet-api-token ${PIVNET_TOKEN} --pivnet-product-slug  ${PRODUCT} --product-version ${PRODUCT_VERSION} --pivnet-file-glob ${PRODUCT_GLOB}

  if [[ ${PRODUCT} == "vmware-nsx-t" ]]; then
    if [[ ${PRODUCT_VERSION} == "3.2.2.2" ]]; then
      PRODUCT_VERSION="3.2.1707xxx"
    elif [[ ${version} == "3.2.2" ]]; then
      PRODUCT_VERSION="3.2.16xxx"
    fi
  fi

  lts_substring="+LTS-T"
  if [[ ${PRODUCT} == "cf" || ${PRODUCT} == "pas-windows" ]]; then
    # don't really need the if check
    # this takes the ${version} and remove the template which is defined as anything ending in "+LTS-T"
    # if the result is empty (-z), then the ${version} did in fact end with that suffix
    # if [[ -z ${version##*$lts_substring} ]]; then
      # Remove the suffix defined in ${lts_substring} from ${version}
      PRODUCT_VERSION=${PRODUCT_VERSION%$lts_substring*}
    # fi
  fi

  wrkdir=$(find ${tmpdir}/${PRODUCT} -name "${PRODUCT_VERSION}*")
  if [ ! -f ${wrkdir}/product.yml ]; then
    echo "Something wrong with configuration as expecting ${wrkdir}/product.yml to exist"
    exit 1
  fi

}

get_new_product_templates










