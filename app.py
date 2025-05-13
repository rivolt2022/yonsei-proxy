import pyodbc
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional # Optional을 사용하거나 Python 3.10+ 에서는 | None 사용
import datetime

# --- 1. Connection Information ---
db_server = "165.132.156.161"
db_name = "DigetSystem"
db_user = "sa"
db_password = "tjdgus123!@" # Please be cautious with security in production environments.

# --- 2. Create Connection String ---
conn_str = (
    f"DRIVER={{FreeTDS}};"
    f"SERVER={db_server};"
    f"PORT=1433;"
    f"DATABASE={db_name};"
    f"UID={db_user};"
    f"PWD={db_password};"
    f"TDS_VERSION=7.2;"
    f"Encrypt=no;"
    f"TrustServerCertificate=yes;"
)

# --- 3. FastAPI Setup ---
app = FastAPI()

# --- 3.1 Health Check Endpoint ---
@app.get("/health")
async def health_check():
    try:
        # 데이터베이스 연결 테스트
        conn = pyodbc.connect(conn_str)
        conn.close()
        return {
            "status": "healthy",
            "database": "connected",
            "timestamp": datetime.datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "unhealthy",
                "database": "disconnected",
                "error": str(e),
                "timestamp": datetime.datetime.now().isoformat()
            }
        )

# --- 4. Define Response Model ---
class WorkResult(BaseModel):
    USERNUMBER: str
    WORKSTART: Optional[str] # DB에서 NULL이 올 수 있으므로 Optional 또는 str | None
    WORKEND: Optional[str]   # DB에서 NULL이 올 수 있으므로 Optional 또는 str | None
    WORKDAY: str             # WORKDAY는 항상 값이 있다고 가정 (쿼리 조건에 사용됨)
    USERID: str

# --- 5. Endpoint to Query Database ---
@app.get("/workresults/{dclz_trns_dt_value}", response_model=List[WorkResult])
async def get_work_results(dclz_trns_dt_value: str):
    conn = None
    try:
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()

        # SQL query 수정: 날짜/시간 필드를 VARCHAR로 변환 (형식: YYYY-MM-DD HH:MM:SS)
        sql_query = """
        SELECT LTRIM(RTRIM(A1.USERNUMBER)) AS USERNUMBER,
               CONVERT(VARCHAR(19), A2.WORKSTART, 120) AS WORKSTART, -- YYYY-MM-DD HH:MI:SS (24h)
               CONVERT(VARCHAR(19), A2.WORKEND, 120) AS WORKEND,     -- YYYY-MM-DD HH:MI:SS (24h)
               CONVERT(VARCHAR(19), A2.WORKDAY, 120) AS WORKDAY,     -- YYYY-MM-DD HH:MI:SS (24h)
               A1.USERID
          FROM TB_USER A1,
               TB_WORKRESULT A2
         WHERE A1.USERID = A2.USERID
           AND CONVERT(CHAR(8), A2.WORKDAY, 112) = ? -- YYYYMMDD 형식으로 비교
           AND LTRIM(RTRIM(A1.USERNUMBER)) IS NOT NULL
           AND (A2.WORKSTART IS NOT NULL OR A2.WORKEND IS NOT NULL)
        """
        cursor.execute(sql_query, dclz_trns_dt_value)
        rows = cursor.fetchall()

        work_results = [
            WorkResult(
                USERNUMBER=row.USERNUMBER,
                WORKSTART=row.WORKSTART, # SQL에서 이미 문자열로 변환됨
                WORKEND=row.WORKEND,     # SQL에서 이미 문자열로 변환됨
                WORKDAY=row.WORKDAY,     # SQL에서 이미 문자열로 변환됨
                USERID=row.USERID
            )
            for row in rows
        ]
        return work_results

    except pyodbc.Error as e:
        print(f"Database error occurred: {e}")
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        raise HTTPException(status_code=500, detail=f"An unexpected error: {str(e)}")
    finally:
        if conn:
            conn.close()
            print("Connection closed.") # 연결 종료 확인용 (선택 사항)

# --- 6. Run the FastAPI app ---
# 터미널에서 이 파일이 있는 디렉토리로 이동한 후 다음 명령어로 실행:
# uvicorn app:app --reload
# (파일 이름이 app.py라고 가정)