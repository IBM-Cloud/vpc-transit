FROM python:3
COPY requirements.txt /tmp
RUN  pip install -r /tmp/requirements.txt \
  && apt-get update \
  && apt-get install -y \
  && apt-get update \
  && apt-get install -y gnupg software-properties-common \
  && wget -O- https://apt.releases.hashicorp.com/gpg | \
     gpg --dearmor | \
     tee /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  && gpg --no-default-keyring \
     --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
     --fingerprint \
  && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/hashicorp.list \
  && apt update \
  && apt-get install terraform \
  && terraform -help \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSL https://clis.cloud.ibm.com/install/linux | sh \
  && ibmcloud plugin install is
