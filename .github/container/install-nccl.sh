#!/bin/bash

set -ex -o pipefail

export DEBIAN_FRONTEND=noninteractive
export TZ=America/Los_Angeles

#apt remove -y libnccl2 libnccl-dev
#pushd /tmp
#NCCL_REPO_AND_BRANCH=https://gitlab-master.nvidia.com/nccl/nccl.git#v2.22.3-1
#REPO_URL=${NCCL_REPO_AND_BRANCH%#*}
#BRANCH_NAME=${NCCL_REPO_AND_BRANCH#*#}
#git clone -b ${BRANCH_NAME} ${REPO_URL}
#cd nccl
#make -j8 src.build
#make pkg.debian.build
#dpkg -i build/pkg/deb/*
#rm -rf /usr/lib/python3/dist-packages/gpg
#rm -rf /usr/lib/python3/dist-packages/gpg-*.egg-info
#rm -rf /usr/lib/python3/dist-packages/xdg-*.egg-info

#If NCCL is already installed, don't reinstall it. Print a message and exit
if dpkg -s libnccl2 libnccl-dev &> /dev/null; then
    echo "NCCL is already installed. Skipping installation."
else
   apt-get update

   # Extract CUDA version from `nvcc --version` output line
   # Input: "Cuda compilation tools, release X.Y, VX.Y.Z"
   # Output: X.Y
   cuda_version=$(nvcc --version | sed -n 's/^.*release \([0-9]*\.[0-9]*\).*$/\1/p')

   # Find latest NCCL version compatible with existing CUDA by matching
   # ${cuda_version} in the package version string
   libnccl2_version=$(apt-cache show libnccl-dev | sed -n "s/^Version: \(.*+cuda${cuda_version}\)$/\1/p" | head -n 1)
   libnccl_dev_version=$(apt-cache show libnccl-dev | sed -n "s/^Version: \(.*+cuda${cuda_version}\)$/\1/p" | head -n 1)
   if [[ -z "${libnccl2_version}" || -z "${libnccl_dev_version}" ]]; then
       echo "Could not find compatible NCCL version for CUDA ${cuda_version}"
       exit 1
   fi

   apt-get install -y \
       --allow-change-held-packages \
       libnccl2=${libnccl2_version} \
       libnccl-dev=${libnccl_dev_version} \

   apt-get clean
   rm -rf /var/lib/apt/lists/*
fi

# Create a prefix with include/ and lib/ directories containing symlinks to the NCCL
# version installed at the system level; this is useful to pass to XLA to avoid it
# fetching its own copy.
prefix=/opt/nvidia/nccl
if [[ -d "${prefix}" ]]; then
  echo "Skipping link farm creation"
  exit 1
fi
arch=$(uname -m)-linux-gnu
for nccl_file in $(dpkg -L libnccl2 libnccl-dev | sort -u); do
  # Real files and symlinks are linked into $prefix
  if [[ -f "${nccl_file}" || -h "${nccl_file}" ]]; then
    # Replace /usr with $prefix and remove arch-specific lib directories
    nosysprefix="${nccl_file#"/usr/"}"
    noarchlib="${nosysprefix/#"lib/${arch}"/lib}"
    link_name="${prefix}/${noarchlib}"
    link_dir=$(dirname "${link_name}")
    mkdir -p "${link_dir}"
    ln -s "${nccl_file}" "${link_name}"
  else
    echo "Skipping ${nccl_file}"
  fi
done
