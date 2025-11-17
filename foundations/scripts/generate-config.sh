##### generate-config.sh

#!/bin/bash -e
: ${PIVNET_TOKEN?"Need to set PIVNET_TOKEN"}

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

select_product

# function generate_config (){
# ---- Get version, glob, slug from version file
echo "Generating configuration for product $PRODUCT"
productfile="../${IAAS}/download-products/${PRODUCT}.yml"
versionfile="../${IAAS}/${FOUNDATION_NAME}/versions/version.yml"

if [ ! -f ${versionfile} ]; then
  echo "Must create ${versionfile}"
  exit 1
fi
version=$(bosh interpolate ${versionfile} --path=/${PRODUCT}-version)
glob=$(bosh interpolate ${productfile} --path=/pivnet-file-glob)
slug=$(bosh interpolate ${productfile} --path=/pivnet-product-slug)

### updating product glob for healthwatch
if [[ ${PRODUCT} == "p-healthwatch2" ]]; then
    glob=healthwatch-${version}*.pivotal
elif [[ ${PRODUCT} == "p-antivirus" ]]; then
    glob=${PRODUCT}-${version}*.pivotal
fi

# ---- Execute om config-template 
tmpdir=tile-configs/${PRODUCT}-config
mkdir -p ${tmpdir}

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
  echo "Something wrong with configuration as expecting ${wrkdir}/product.yml to exist"
  exit 1
fi

# ---- Create array of opsfiles to apply
mkdir -p ../${IAAS}/opsfiles
ops_files="../${IAAS}/${FOUNDATION_NAME}/opsfiles/${PRODUCT}-operations"
touch ${ops_files}

ops_files_args=("")
custom_ops_files_args=("")

if [ -f ../${IAAS}/${FOUNDATION_NAME}/opsfiles/${PRODUCT}-custom.yml ]; then
    custom_ops_files_args+="-o ../${IAAS}/${FOUNDATION_NAME}/opsfiles/${PRODUCT}-custom.yml"
fi

while IFS= read -r var
do
  ops_files_args+=("-o ${wrkdir}/${var}")
  # echo "inside  ${ops_files_args[@]}" 
done < "$ops_files"

# echo "wrk dir is : ${wrkdir}"
# echo "ops file is $ops_files"


# echo "final:  ${ops_files_args[@]}"

# ---- Create template file from product.yml with applied opsfiles
echo "Creating template file from ${PRODUCT}.yml with applied opsfiles"
mkdir -p ../${IAAS}/${FOUNDATION_NAME}/config/templates
#mv ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}.yml ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}-current.yml
bosh int ${wrkdir}/product.yml ${ops_files_args[@]} ${custom_ops_files_args[@]} > ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}.yml

# git diff ../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}.yml
# ---- Set up for creation of defaults file
mkdir -p ../${IAAS}/${FOUNDATION_NAME}/config/defaults
rm -rf ../${IAAS}/${FOUNDATION_NAME}/config/defaults/${PRODUCT}.yml
touch ../${IAAS}/${FOUNDATION_NAME}/config/defaults/${PRODUCT}.yml

# ---- Add default vars to defaults file
echo "Adding default vars to ${PRODUCT} defaults file"
if [ -f ${wrkdir}/default-vars.yml ]; then
  vars=$(cat ${wrkdir}/default-vars.yml | tr -d '[:space:]')
  if [[ "${vars}" != "" && "${vars}" != "{}" ]]; then
    cat ${wrkdir}/default-vars.yml >> ../${IAAS}/${FOUNDATION_NAME}/config/defaults/${PRODUCT}.yml
  fi
fi

# ---- Add errands vars to ${PRODUCT} defaults file
echo "Add errands vars to ${PRODUCT} defaults file"
if [ -f ${wrkdir}/errand-vars.yml ]; then
  vars=$(cat ${wrkdir}/errand-vars.yml | tr -d '[:space:]')
  if [[ "${vars}" != "" && "${vars}" != "{}" ]]; then
    cat ${wrkdir}/errand-vars.yml >> ../${IAAS}/${FOUNDATION_NAME}/config/defaults/${PRODUCT}.yml
  fi
fi

# ---- Add resource vars to defaults file
echo "Add resource vars to ${PRODUCT} defaults file"
if [ -f ${wrkdir}/resource-vars.yml ]; then
  vars=$(cat ${wrkdir}/resource-vars.yml | tr -d '[:space:]')
  if [[ "${vars}" != "" && "${vars}" != "{}" ]]; then
    cat ${wrkdir}/resource-vars.yml >> ../${IAAS}/${FOUNDATION_NAME}/config/defaults/${PRODUCT}.yml
  fi
fi

# ---- Ensure secrets file exists
mkdir -p ../${IAAS}/${FOUNDATION_NAME}/config/secrets
touch ../${IAAS}/${FOUNDATION_NAME}/config/secrets/${PRODUCT}.yml

# ---- Ensure vars file exists
mkdir -p ../${IAAS}/${FOUNDATION_NAME}/config/vars
touch ../${IAAS}/${FOUNDATION_NAME}/config/vars/${PRODUCT}.yml

# ---- Ensure common vars file exists
mkdir -p ../${IAAS}/common
touch ../${IAAS}/common/${PRODUCT}.yml

echo "Generation of configuration files has succeeded."


# ---- Prune unused variables from defaults file using grep and awk
defaults_file="../${IAAS}/${FOUNDATION_NAME}/config/defaults/${PRODUCT}.yml"
template_file="../${IAAS}/${FOUNDATION_NAME}/config/templates/${PRODUCT}.yml"

if [ -f "${defaults_file}" ] && [ -f "${template_file}" ]; then
  echo "Pruning unused variables from defaults file..."

  # Extract all ((var_name)) references from the template
  used_vars=$(grep -o '\(\([^()]*\)\)' "${template_file}" | tr -d '()' | sort -u | grep -v ":")

  # Create a temp file to store cleaned defaults
  tmp_cleaned=$(mktemp)

  # Read the defaults file line by line
  while IFS= read -r line; do
    # Extract the variable name from the line (before the colon)
    ###ANOTHER WAY of doing it --->. varname=$(echo "$line" | sed -n 's/^\([^:]*\):.*/\1/p')
    varname=$(echo "$line" | awk -F ":" '{print $1}')
    if [ -n "$varname" ] && echo "$used_vars" | grep -qx "$varname"; then
      echo "$line" >> "$tmp_cleaned"
    fi
  done < "$defaults_file"

  mv "$tmp_cleaned" "$defaults_file"
  echo "Removed unused variables from defaults file."
fi


######### end of generate-config