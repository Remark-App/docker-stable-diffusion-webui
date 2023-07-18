ARG BASEIMAGE
ARG BASETAG

# STAGE FOR CACHING APT PACKAGE LIST
FROM ${BASEIMAGE}:${BASETAG} as stage_apt

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN \
    rm -rf /etc/apt/apt.conf.d/docker-clean \
	&& echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache \
	&& apt-get update

# STAGE FOR INSTALLING APT DEPENDENCIES
FROM ${BASEIMAGE}:${BASETAG} as stage_deps

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

COPY deps/aptDeps.txt /tmp/aptDeps.txt

# INSTALL APT DEPENDENCIES USING CACHE OF stage_apt
RUN \
    --mount=type=cache,target=/var/cache/apt,from=stage_apt,source=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt,from=stage_apt,source=/var/lib/apt \
    --mount=type=cache,target=/etc/apt/sources.list.d,from=stage_apt,source=/etc/apt/sources.list.d \
	apt-get install --no-install-recommends -y $(cat /tmp/aptDeps.txt) \
    && rm -rf /tmp/*


# STAGE FOR BUILDING APPLICATION CONTAINER
FROM stage_deps as stage_app

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV \
    DEBIAN_FRONTEND=noninteractive \
    FORCE_CUDA=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LD_LIBRARY_PATH=/usr/local/cuda-11.7/lib64:$LD_LIBRARY_PATH \
    NVCC_FLAGS="--use_fast_math -DXFORMERS_MEM_EFF_ATTENTION_DISABLE_BACKWARD"\
    PATH=/usr/local/cuda-11.7/bin:$PATH \
    TORCH_CUDA_ARCH_LIST="6.0;6.1;6.2;7.0;7.2;7.5;8.0;8.6" \
    XFORMERS_DISABLE_FLASH_ATTN=1

# SWITCH TO THE GENERATED USER
WORKDIR /app

# CLONE AND PREPARE FOR THE SETUP OF SD-WEBUI
RUN \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git \
    # CHECKOUT TO COMMIT 955df7751eef11bb7697e2d77f6b8a6226b21e13
    && git -C stable-diffusion-webui reset --hard f865d3e

RUN \
    mkdir /app/stable-diffusion-webui/outputs \
    && mkdir /app/stable-diffusion-webui/styles

RUN /app/stable-diffusion-webui/webui.sh -f --skip-torch-cuda-test --no-download-sd-model --exit

# INSTALL PYTHON DEPENDENCIES THAT ARE NOT INSTALLED BY THE SCRIPT
COPY deps/pyDeps.txt /tmp/pyDeps.txt

RUN \
    python3 -m venv stable-diffusion-webui/venv \
    && source stable-diffusion-webui/venv/bin/activate \
    && python3 -m pip install $(cat /tmp/pyDeps.txt) \
    && rm -rf /tmp/*

# COPY entrypoint.sh
COPY --chmod=775 scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /app/stable-diffusion-webui
USER root

# PORT AND ENTRYPOINT, USER SETTINGS
#EXPOSE 7860
#ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]

# DOCKER IAMGE LABELING
LABEL title="Stable-Diffusion-Webui-Docker"
LABEL version="1.3.2"

# ---------- BUILD COMMAND ----------
# DOCKER_BUILDKIT=1 docker build --no-cache \
# --build-arg BASEIMAGE=nvidia/cuda \
# --build-arg BASETAG=11.7.1-cudnn8-devel-ubuntu22.04 \
# -t kestr3l/stable-diffusion-webui:1.2.2 \
# -f Dockerfile .