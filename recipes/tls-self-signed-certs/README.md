# Camunda 8 Helm Recipe: Self Signed TLS Certificates 

This folder contains a [Makefile](Makefile) that demonstrates how to create certificates and keystores

## Features

This recipe provides:
- **Certificate Authority CA**: Create a self signed certificate authority
- **TLS Certificate**: create a self signed tls certificate
- **Keystore and Truststore**: create java keystore and truststores

## Prerequisites

- The java `keytool` cli installed
- GNU `make`

## Usage

Open a terminal and run `make` to generate a CA certificate, tls cert, keystore, and truststore. 

Run `make clean` to delete the generated files
