FROM rocker/rstudio:latest

# 1. Add r2u repository (amd64 only — on arm64 this is a no-op and apt
#    falls back to CRAN source builds transparently via install.packages()).
#    r2u provides pre-built .deb packages for all of CRAN and Bioconductor,
#    cutting R package installation from minutes to seconds on amd64.
#
#    The key is ASCII-armored (.asc) and must be dearmored before saving.
#    The entire block is wrapped in || true so a network hiccup does not
#    break the build — it just falls back to source installs.
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget ca-certificates gpg \
    && ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then \
        ( wget -q -O- \
            https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc \
          | gpg --dearmor > /usr/share/keyrings/r2u-keyring.gpg \
        && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/r2u-keyring.gpg] \
              https://r2u.stat.chicago.edu/ubuntu noble main" \
            > /etc/apt/sources.list.d/r2u.list \
        && apt-get update \
        ) || ( \
            echo "WARNING: r2u setup failed — falling back to CRAN source builds" && \
            rm -f /etc/apt/sources.list.d/r2u.list \
                  /usr/share/keyrings/r2u-keyring.gpg \
        ); \
    fi \
    && rm -rf /var/lib/apt/lists/*

# 2. System tools: Valgrind, Linux Perf, Google Performance Tools, build deps,
#    and libraries needed by ellmer/btw and the packages they depend on.
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

# 3. R packages — installed via apt (r2u binary) on amd64, CRAN source on arm64.
#    On amd64 each line resolves in seconds; on arm64 apt finds nothing and
#    install.packages() compiles from source as before.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            r-cran-profvis \
            r-cran-bench \
            r-cran-memoise \
            r-cran-xml2 \
            r-cran-ellmer \
            r-cran-btw \
        && rm -rf /var/lib/apt/lists/*; \
    else \
        R -e "install.packages( \
            c('profvis','bench','memoise','xml2','mcptools','ellmer','btw'), \
            repos='https://cloud.r-project.org/')"; \
    fi

WORKDIR /workspace

# 4. Copy the demonstration package source
COPY profdemo/ /workspace/profdemo/

# 5. Build and install profdemo (compiles the C code)
RUN R CMD INSTALL /workspace/profdemo

# 6. Copy top-level demo scripts
COPY scripts/ /workspace/scripts/

# 7. Make shell demo scripts executable
RUN find /workspace -name "*.sh" -exec chmod +x {} \;

# RStudio Server listens on 8787; default credentials are rstudio / rstudio
EXPOSE 8787
