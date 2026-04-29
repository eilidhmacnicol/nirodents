ARG TARGETARCH

# Empty placeholder — amd64 gets ANTs via pixi/conda-forge
FROM alpine AS ants-amd64
RUN mkdir -p /opt/ants

# Pre-built arm64 binaries
FROM ghcr.io/nipreps/ants:2.6.5-arm64 AS ants-arm64

FROM ants-${TARGETARCH} AS ants-current


FROM ghcr.io/prefix-dev/pixi:0.53.0 AS build
RUN apt-get update && \
apt-get install -y --no-install-recommends \
build-essential \
ca-certificates \
git && \
apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN pixi config set --global run-post-link-scripts insecure

RUN mkdir /app
COPY pixi.lock pyproject.toml /app/
WORKDIR /app
COPY . /app
RUN --mount=type=cache,target=/root/.cache/rattler pixi install -e nirodents --frozen
RUN pixi shell-hook -e nirodents --as-is | grep -v PATH > /shell-hook.sh

FROM ubuntu:resolute-20260413

# Create a shared $HOME directory
RUN useradd -m -s /bin/bash -G users nirodents
ENV HOME="/home/nirodents"

# Unless otherwise specified each process should only use one thread - nipype
# will handle parallelization
ENV MKL_NUM_THREADS=1 \
OMP_NUM_THREADS=1 \
TEMPLATEFLOW_AUTOUPDATE=0

# No-op for amd64, copies real binaries for arm64
COPY --from=ants-current /opt/ants /opt/ants

COPY --from=build /shell-hook.sh /shell-hook.sh
COPY --from=build /app/.pixi/envs/nirodents /app/.pixi/envs/nirodents
RUN cat /shell-hook.sh >> $HOME/.bashrc
ENV PATH="/app/.pixi/envs/nirodents/bin:/opt/ants/bin:$PATH"

COPY docker/files/nipype.cfg /home/nirodents/.nipype/nipype.cfg

# Cleanup and ensure perms.
RUN find $HOME -type d -exec chmod go=u {} + && \
    find $HOME -type f -exec chmod go=u {} +

# Final settings
WORKDIR /tmp
ARG BUILD_DATE
ARG VCS_REF
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="nirodents" \
      org.label-schema.description="nirodents - NeuroImaging workflows" \
      org.label-schema.url="https://github.com/nipreps/nirodents" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/nipreps/nirodents" \
      org.label-schema.schema-version="1.0"

ENTRYPOINT ["/app/.pixi/envs/nirodents/bin/artsBrainExtraction"]
