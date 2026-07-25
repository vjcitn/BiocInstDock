FROM rocker/r-ver:latest

# 1. System tools: Valgrind, Linux Perf, Google Performance Tools, build deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    valgrind \
    linux-tools-generic \
    google-perftools \
    libgoogle-perftools-dev \
    build-essential \
    graphviz \
    git \
    && rm -rf /var/lib/apt/lists/*

# 2. R-level profiling and benchmarking packages
RUN R -e "install.packages(c('profvis', 'bench', 'memoise'), repos='https://cloud.r-project.org/')"

WORKDIR /workspace

# 3. Copy the demonstration package source
COPY profdemo/ /workspace/profdemo/

# 4. Build and install profdemo (compiles the C code)
RUN R CMD INSTALL /workspace/profdemo

# 5. Copy top-level demo scripts
COPY scripts/ /workspace/scripts/

# 6. Make shell demo scripts executable
RUN find /workspace -name "*.sh" -exec chmod +x {} \;

# Default: drop into an interactive R session
CMD ["R", "--vanilla"]
