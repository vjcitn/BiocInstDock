FROM rocker/rstudio:latest

# 1. System tools: Valgrind, Linux Perf, Google Performance Tools, build deps,
#    and libraries needed for ellmer/btw (curl, ssl, libuv) and Rust toolchain
#    (required by the savvy crate used by some LLM packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
    valgrind \
    linux-tools-generic \
    google-perftools \
    libgoogle-perftools-dev \
    build-essential \
    graphviz \
    git \
    libuv1-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    rustc \
    cargo \
    libxml2-dev \
    zlib1g-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 2. R-level profiling, benchmarking, and LLM packages
RUN R -e "install.packages(c('profvis', 'bench', 'memoise', 'xml2', 'mcptools', 'ellmer', 'btw'), repos='https://cloud.r-project.org/')"

WORKDIR /workspace

# 3. Copy the demonstration package source
COPY profdemo/ /workspace/profdemo/

# 4. Build and install profdemo (compiles the C code)
RUN R CMD INSTALL /workspace/profdemo

# 5. Copy top-level demo scripts
COPY scripts/ /workspace/scripts/

# 6. Make shell demo scripts executable
RUN find /workspace -name "*.sh" -exec chmod +x {} \;

# RStudio Server listens on 8787; default credentials are rstudio / rstudio
EXPOSE 8787
