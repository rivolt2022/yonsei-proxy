# Base image: Ubuntu 18.04 LTS
FROM ubuntu:18.04

# 기본 환경 설정
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# 패키지 목록 업데이트 및 기본 유틸리티 설치
# software-properties-common: add-apt-repository 사용 위함
# ca-certificates: HTTPS 연결 위함
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    software-properties-common \
    curl \
    wget \
    lsb-release \
    apt-transport-https \
    ca-certificates \
    vim \
    gcc \
    g++ \
    unixodbc-dev && \
    # 이전 단계에서 생성된 apt 목록 정리
    rm -rf /var/lib/apt/lists/*

# Deadsnakes PPA 추가, 패키지 목록 업데이트, Python 3.8 및 관련 도구 설치를 단일 RUN 명령으로 통합
RUN add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.8 \
        python3.8-dev \
        python3.8-distutils \
        python3.8-venv && \
    # get-pip.py를 사용하여 pip 설치
    curl https://bootstrap.pypa.io/pip/3.8/get-pip.py -o get-pip.py && \
    python3.8 get-pip.py && \
    rm get-pip.py && \
    # 이 단계에서 생성된 apt 목록 정리
    rm -rf /var/lib/apt/lists/*

# FreeTDS 설치 (ODBC 드라이버 대체)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        freetds-dev \
        freetds-bin \
        tdsodbc \
        unixodbc-dev \
        unixodbc \
        libodbc1 \
        odbcinst \
        odbcinst1debian2 && \
    rm -rf /var/lib/apt/lists/*

# FreeTDS 설정
RUN echo "[FreeTDS]" > /etc/odbcinst.ini && \
    echo "Description = FreeTDS Driver" >> /etc/odbcinst.ini && \
    echo "Driver = /usr/lib/x86_64-linux-gnu/odbc/libtdsodbc.so" >> /etc/odbcinst.ini && \
    echo "Setup = /usr/lib/x86_64-linux-gnu/odbc/libtdsS.so" >> /etc/odbcinst.ini && \
    echo "UsageCount = 1" >> /etc/odbcinst.ini && \
    # 드라이버 파일 존재 여부 확인
    ls -l /usr/lib/x86_64-linux-gnu/odbc/libtdsodbc.so || echo "Driver file not found"

# OpenSSL 설정을 변경하여 TLS 1.0 지원 활성화
# Ubuntu 18.04의 OpenSSL 1.1.1은 TLS 1.0을 지원하지만, 기본 보안 수준(SECLEVEL=2)에서 비활성화될 수 있음
# SECLEVEL을 1로 낮추고, MinProtocol이 TLSv1.2 이상으로 설정된 경우 TLSv1.0으로 변경합니다.
RUN OPENSSL_CONF_FILE="/etc/ssl/openssl.cnf" && \
    if [ -f "$OPENSSL_CONF_FILE" ]; then \
        echo "Modifying $OPENSSL_CONF_FILE for TLS 1.0 support..."; \
        cp "$OPENSSL_CONF_FILE" "$OPENSSL_CONF_FILE.bak.$(date +%s)"; \
        # MinProtocol이 TLSv1.2 또는 TLSv1.3으로 설정된 경우 TLSv1.0으로 변경
        sed -i 's/^\(MinProtocol\s*=\s*TLSv1\.\)[23]/\10/' "$OPENSSL_CONF_FILE"; \
        # CipherString의 SECLEVEL이 2 이상인 경우 1로 변경
        sed -i 's/\(CipherString\s*=\s*.*@SECLEVEL=\)[2-9]/\11/' "$OPENSSL_CONF_FILE"; \
        # 만약 CipherString이 SECLEVEL 없이 정의되어 있다면, @SECLEVEL=1 추가 (예: CipherString = DEFAULT -> CipherString = DEFAULT@SECLEVEL=1)
        # 이는 CipherString이 한 줄에 정의되어 있다고 가정합니다.
        if grep -q "^\s*CipherString\s*=" "$OPENSSL_CONF_FILE" && ! grep -q "^\s*CipherString\s*=.*@SECLEVEL=" "$OPENSSL_CONF_FILE"; then \
            sed -i -E 's/^(\s*CipherString\s*=[^@#]+)(#.*)?$/\1@SECLEVEL=1 \2/' "$OPENSSL_CONF_FILE"; \
        fi; \
        echo "Relevant lines from $OPENSSL_CONF_FILE after modification attempt:"; \
        grep -E "^MinProtocol|^CipherString|^\\[system_default_sect\\]" "$OPENSSL_CONF_FILE" || echo "No matching lines found in $OPENSSL_CONF_FILE."; \
    else \
        echo "$OPENSSL_CONF_FILE not found."; \
    fi

# OpenSSL 버전 확인 및 TLS 1.0 지원 테스트 (선택 사항)
RUN openssl version && \
    echo "To test TLS 1.0 connectivity, you might use: openssl s_client -connect your-tls1.0-server:443 -tls1"

# 작업 디렉토리 설정
WORKDIR /app

# Python 의존성 설치 (requirements.txt 파일 필요)
COPY requirements.txt .
RUN python3.8 -m pip install --no-cache-dir -r requirements.txt

# 애플리케이션 코드 복사 (app.py 파일 필요)
COPY app.py .

# 애플리케이션 포트 노출
EXPOSE 8000

# 컨테이너 실행 시 FastAPI 애플리케이션 실행 명령어
CMD ["python3.8", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]