FROM --platform=$BUILDPLATFORM public.ecr.aws/amazonlinux/amazonlinux:latest as build-server

# Set architecture as build arg with default to amd64
ARG TARGETARCH=amd64
ARG BUILDPLATFORM
# Set OpenSSL version as build arg with default to 1.1.1n (compatible with UE 5.1, 5.2)
ARG OPENSSL_VERSION=1.1.1n

# Install basic dependencies
RUN yum install -y gcc-c++ gdb cmake3 git wget openssl openssl-devel tar perl sudo

# Install architecture-specific dependencies
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      echo "Installing ARM64 specific tools..." && \
      yum install -y binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu g++-aarch64-linux-gnu; \
    fi

# Format OpenSSL version string for download URL
RUN echo "Configuring OpenSSL version ${OPENSSL_VERSION}" && \
    OPENSSL_FORMAT_VERSION=$(echo "${OPENSSL_VERSION}" | tr '.' '_')

# Install correct OpenSSL version based on build arg
RUN wget https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_').tar.gz && \
tar -xzvf OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_').tar.gz && \
cd openssl-OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_')/ && \
# Configure with arch-specific optimization flags
if [ "$TARGETARCH" = "arm64" ]; then \
  # ARM64-specific configuration
  ./config -march=armv8-a; \
else \
  # AMD64-specific configuration
  ./config -m64; \
fi && \
sudo make install

RUN export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64 && \
openssl version && \
cd ..

# Copy the Open SSL files to binaries folder
RUN mkdir -p /binaries/${TARGETARCH} && \
cp ./openssl-OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_')/libssl.so.1.1 /binaries/${TARGETARCH}/ && \
cp ./openssl-OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_')/libcrypto.so.1.1 /binaries/${TARGETARCH}/

# Download and build the GameLift Server SDK (NOTE: You might need to change this to download a different SDK version)
RUN echo "Download and unzip GameLift Server SDK 5.2.0" && \
mkdir SDK && cd SDK && \
wget https://gamelift-server-sdk-release.s3.us-west-2.amazonaws.com/cpp/GameLift-Cpp-ServerSDK-5.2.0.zip && \
unzip GameLift-Cpp-ServerSDK-5.2.0.zip && \
echo "Build the GameLift server SDK" && \
mkdir cmake-build

# Configure CMake with architecture-specific flags
RUN cd SDK && \
if [ "$TARGETARCH" = "arm64" ]; then \
  echo "Configuring for ARM64..." && \
  cmake -G "Unix Makefiles" -DBUILD_FOR_UNREAL=1 -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-march=armv8-a" -S . -B ./cmake-build; \
else \
  echo "Configuring for AMD64..." && \
  cmake -G "Unix Makefiles" -DBUILD_FOR_UNREAL=1 -DCMAKE_BUILD_TYPE=Release -S . -B ./cmake-build; \
fi

# Build the SDK
RUN cd SDK && \
cmake --build cmake-build --target all && \
cd ./cmake-build/prefix/ && \
echo "Copying files over to binaries folder" && \
cp -r ./lib/*  /binaries/${TARGETARCH}/ && \
echo "copying over headers (these are already provided by the GameLift Unreal Plugin so you don't need them with that)" && \
mkdir -p /binaries/${TARGETARCH}/include && \
cp -r ./include/*  /binaries/${TARGETARCH}/include/

# Copy the binaries only to a clean setup for copying to local system after build
FROM scratch AS server
  ARG TARGETARCH=amd64
  COPY --from=build-server /binaries/${TARGETARCH}/ /
  ENTRYPOINT [ "/GameLiftSampleServer" ]

