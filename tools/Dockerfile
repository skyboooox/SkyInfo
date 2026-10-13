FROM ghcr.io/cirruslabs/flutter:3.44.0@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8
RUN sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
RUN sdkmanager 'cmake;3.22.1'
WORKDIR /workspace
