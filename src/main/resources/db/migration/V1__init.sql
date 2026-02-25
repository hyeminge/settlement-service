-- ============================================================================
-- Medi-Flow Portal 정산 시스템 DDL
-- 작성자: 혜민 (정산팀)
-- 버전: 11.0
-- DBMS: MySQL 8.0+
--
-- 변경사항 (v11.0):
--   ❌ is_active 제거 (정책 테이블 3개) → 선생님 피드백
--   ❌ created_by 제거 (정책 테이블 3개) → 한 명 운영
--   ❌ vendor_cache, product_cache 제거 → 선생님 피드백
--   ✅ vendor_revenue_rate GENERATED (100 - platform_fee_rate 자동계산)
--   ✅ sales_ledger: fail_reason, hospital_name 추가 (배치 실패 추적)
--   ✅ platform_revenue: operating_profit/net_revenue GENERATED 정리
--
-- [총 테이블: 9개]
--   1. platform_fee_policy
--   2. driver_fee_policy
--   3. settlement_price_policy
--   4. settlement_batch
--   5. sales_ledger
--   6. payout_ledger
--   7. platform_revenue
--   8. vat_summary
--   9. settlement_event_log
--  10. sales_ledger_snapshot
--  11. payout_ledger_snapshot
-- ============================================================================


-- ============================================================================
-- 테이블 1: platform_fee_policy (플랫폼 요금 정책)
-- ============================================================================
CREATE TABLE platform_fee_policy (
                                     fee_policy_id               BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '요금 정책 ID',

    -- 구독 요금
                                     subscription_monthly_fee    DECIMAL(10,2) NOT NULL COMMENT '월 구독료 (병원당 정액)',

    -- 미구독 배송비
                                     non_subscriber_delivery_fee DECIMAL(10,2) NOT NULL COMMENT '미구독 병원 건당 배송비',

    -- 보관료
                                     storage_fee_per_unit_per_day DECIMAL(10,2) NOT NULL COMMENT '보관료 (개당/일당)',

    -- 유효 기간
                                     effective_from DATE NOT NULL COMMENT '적용 시작일',
                                     effective_to   DATE NOT NULL COMMENT '적용 종료일',

    -- 메타데이터
                                     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',

    -- 인덱스
                                     INDEX idx_effective (effective_from, effective_to),

    -- 체크 제약
                                     CONSTRAINT chk_platform_fees_positive CHECK (
                                         subscription_monthly_fee > 0
                                             AND non_subscriber_delivery_fee > 0
                                             AND storage_fee_per_unit_per_day > 0
                                         ),
                                     CONSTRAINT chk_platform_period CHECK (effective_to >= effective_from)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='플랫폼 요금 정책 (구독료 / 미구독 배송비 / 보관료)';


-- ============================================================================
-- 테이블 2: driver_fee_policy (배송기사 지급 정책)
-- ============================================================================
CREATE TABLE driver_fee_policy (
                                   driver_fee_policy_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '기사 요금 정책 ID',

    -- 배송 건당 지급액
                                   delivery_fee DECIMAL(10,2) NOT NULL COMMENT '배송 건당 기사 지급액',

    -- 유효 기간
                                   effective_from DATE NOT NULL COMMENT '적용 시작일',
                                   effective_to   DATE NOT NULL COMMENT '적용 종료일',

    -- 메타데이터
                                   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',

    -- 인덱스
                                   INDEX idx_effective (effective_from, effective_to),

    -- 체크 제약
                                   CONSTRAINT chk_driver_fee_positive CHECK (delivery_fee > 0),
                                   CONSTRAINT chk_driver_period CHECK (effective_to >= effective_from)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='배송기사 지급 정책 (건당 단일 요금)';


-- ============================================================================
-- 테이블 3: settlement_price_policy (업체 수수료 정책)
-- ============================================================================
CREATE TABLE settlement_price_policy (
                                         price_policy_id     BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '가격 정책 ID',
                                         policy_version      INT NOT NULL COMMENT '정책 버전',

    -- 기본 정보 (MSA - 외부 서비스 참조)
                                         product_id          VARCHAR(50) NOT NULL COMMENT '상품 ID (쇼핑몰 서비스)',
                                         vendor_id           VARCHAR(50) NOT NULL COMMENT '위탁 업체 ID (쇼핑몰 서비스)',

    -- 판매가
                                         sales_price         DECIMAL(10,2) NOT NULL COMMENT '판매가',

    -- 위탁 수수료 정책 (업체별 차등)
                                         platform_fee_rate   DECIMAL(5,2) DEFAULT 20.00 COMMENT '플랫폼 수수료율(%) - 기본 20%',
                                         vendor_revenue_rate DECIMAL(5,2) GENERATED ALWAYS AS (
                                             100.00 - platform_fee_rate
                                             ) STORED COMMENT '업체 수익률(%) - 자동계산 (100 - 플랫폼수수료율)',
                                         fee_policy_type     ENUM('STANDARD', 'VIP', 'NEW') DEFAULT 'STANDARD'
        COMMENT '수수료 정책 유형 (STANDARD:20/80, VIP:10/90, NEW:30/70)',

    -- 유효 기간
                                         effective_from DATE NOT NULL COMMENT '적용 시작일',
                                         effective_to   DATE NOT NULL COMMENT '적용 종료일',

    -- 메타데이터
                                         created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',

    -- 인덱스
                                         INDEX idx_product (product_id),
                                         INDEX idx_vendor (vendor_id),
                                         INDEX idx_effective (effective_from, effective_to),
                                         INDEX idx_fee_policy_type (fee_policy_type),
                                         UNIQUE KEY uk_product_version (product_id, policy_version),

    -- 체크 제약
                                         CONSTRAINT chk_sales_price_positive CHECK (sales_price > 0),
                                         CONSTRAINT chk_effective_period CHECK (effective_to >= effective_from),
                                         CONSTRAINT chk_platform_fee_rate CHECK (platform_fee_rate > 0 AND platform_fee_rate < 100)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='업체 수수료 정책 (위탁판매 - MSA)';


-- ============================================================================
-- 테이블 4: settlement_batch (정산 배치)
-- ============================================================================
CREATE TABLE settlement_batch (
                                  settlement_batch_id  BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '정산 배치 ID',

    -- 배치 정보
                                  batch_type           ENUM('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') NOT NULL COMMENT '배치 유형',
                                  target_period_start  DATE NOT NULL COMMENT '정산 대상 시작일',
                                  target_period_end    DATE NOT NULL COMMENT '정산 대상 종료일',

    -- 실행 정보
                                  started_at           TIMESTAMP NULL COMMENT '시작 시각',
                                  ended_at             TIMESTAMP NULL COMMENT '종료 시각',
                                  duration_seconds     INT COMMENT '실행 소요 시간(초)',
                                  status               ENUM('PENDING', 'RUNNING', 'COMPLETED', 'FAILED', 'PARTIAL_SUCCESS')
        NOT NULL DEFAULT 'PENDING' COMMENT '실행 상태',

    -- 처리 통계
                                  total_processed_count INT DEFAULT 0 COMMENT '총 처리 건수',
                                  success_count         INT DEFAULT 0 COMMENT '성공 건수',
                                  failed_count          INT DEFAULT 0 COMMENT '실패 건수',
                                  hold_count            INT DEFAULT 0 COMMENT '보류 건수',

    -- 금액
                                  net_revenue           DECIMAL(15,2) DEFAULT 0 COMMENT '순수익',

    -- Slack 알림
                                  slack_notification_sent BOOLEAN DEFAULT FALSE COMMENT 'Slack 알림 발송 여부',

    -- 메타데이터
                                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',

    -- 인덱스
                                  INDEX idx_batch_type (batch_type),
                                  INDEX idx_status (status),
                                  INDEX idx_target_period (target_period_start, target_period_end),
                                  INDEX idx_created_at (created_at DESC),

    -- 체크 제약
                                  CONSTRAINT chk_period_valid CHECK (target_period_end >= target_period_start),
                                  CONSTRAINT chk_counts_valid CHECK (
                                      total_processed_count = success_count + failed_count + hold_count
                                      ),
                                  CONSTRAINT chk_duration_positive CHECK (duration_seconds IS NULL OR duration_seconds >= 0)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='정산 배치';


-- ============================================================================
-- 테이블 5: sales_ledger (매출 원장)
-- ============================================================================
CREATE TABLE sales_ledger (
                              sales_ledger_id     BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '매출 원장 ID',
                              settlement_batch_id BIGINT COMMENT '정산 배치 ID (배치 처리 전 NULL)',
                              price_policy_id     BIGINT NOT NULL COMMENT '가격 정책 ID',

    -- 거래 정보 (MSA - 외부 서비스 참조)
                              order_id            VARCHAR(50) NOT NULL COMMENT '주문 ID (쇼핑몰 서비스)',
                              product_id          VARCHAR(50) NOT NULL COMMENT '상품 ID (쇼핑몰 서비스)',
                              hospital_id         VARCHAR(50) NOT NULL COMMENT '병원 ID (쇼핑몰 서비스)',

    -- 수량 및 금액
                              quantity            INT NOT NULL COMMENT '수량',
                              unit_price          DECIMAL(10,2) NOT NULL COMMENT '단가',
                              total_amount        DECIMAL(12,2) NOT NULL COMMENT '합계 금액 (수량 × 단가)',

    -- 구독 여부 및 배송비 (주문 시점 스냅샷)
                              is_subscribed       BOOLEAN NOT NULL COMMENT '주문 시점 구독 여부 (구독: 배송비 무료)',
                              delivery_fee        DECIMAL(10,2) NOT NULL DEFAULT 0
                                  COMMENT '배송비 (구독: 0원 / 미구독: 건당 3,000원)',

    -- 정산 상태
                              settlement_status   ENUM('PENDING', 'CONFIRMED', 'CANCELLED')
        NOT NULL DEFAULT 'PENDING' COMMENT '정산 상태',

    -- 배치 실패 추적
                              fail_reason         VARCHAR(255) NULL COMMENT '정산 실패 사유 (배치 실패 시 기록)',

    -- 메타데이터
                              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',

    -- 내부 FK
                              FOREIGN KEY (settlement_batch_id)
                                  REFERENCES settlement_batch(settlement_batch_id) ON DELETE RESTRICT,
                              FOREIGN KEY (price_policy_id)
                                  REFERENCES settlement_price_policy(price_policy_id) ON DELETE RESTRICT,

    -- 인덱스
                              INDEX idx_batch (settlement_batch_id),
                              INDEX idx_order (order_id),
                              INDEX idx_hospital (hospital_id),
                              INDEX idx_product (product_id),
                              INDEX idx_status (settlement_status),
                              INDEX idx_subscribed (is_subscribed),
                              INDEX idx_hospital_batch (hospital_id, settlement_batch_id),
                              INDEX idx_failed (settlement_batch_id, settlement_status),
                              INDEX idx_created_at (created_at DESC),

    -- 체크 제약
                              CONSTRAINT chk_quantity_positive CHECK (quantity > 0),
                              CONSTRAINT chk_delivery_fee CHECK (
                                  (is_subscribed = TRUE AND delivery_fee = 0) OR
                                  (is_subscribed = FALSE AND delivery_fee >= 0)
                                  )

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='매출 원장 (구독/미구독 배송비 구조 - MSA)';


-- ============================================================================
-- 테이블 6: payout_ledger (지급 원장 - 배송기사)
-- ============================================================================
CREATE TABLE payout_ledger (
                               payout_ledger_id    BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '지급 원장 ID',
                               settlement_batch_id BIGINT COMMENT '정산 배치 ID (배치 처리 전 NULL)',

    -- 배송 정보 (MSA - 외부 서비스 참조)
                               delivery_id         VARCHAR(50) NOT NULL COMMENT '배송 ID (배송 서비스)',
                               driver_id           VARCHAR(50) NOT NULL COMMENT '기사 ID (배송 서비스)',

    -- 지급 금액 (건당 단일 요금)
                               payout_amount       DECIMAL(10,2) NOT NULL COMMENT '기사 지급액 (건당 3,000원)',

    -- 정산 상태
                               settlement_status   ENUM('PENDING', 'CONFIRMED', 'CANCELLED')
        NOT NULL DEFAULT 'PENDING' COMMENT '정산 상태',

    -- 메타데이터
                               created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',

    -- 내부 FK
                               FOREIGN KEY (settlement_batch_id)
                                   REFERENCES settlement_batch(settlement_batch_id) ON DELETE RESTRICT,

    -- 인덱스
                               INDEX idx_batch (settlement_batch_id),
                               INDEX idx_delivery (delivery_id),
                               INDEX idx_driver (driver_id),
                               INDEX idx_status (settlement_status),
                               INDEX idx_driver_batch (driver_id, settlement_batch_id),
                               INDEX idx_created_at (created_at DESC),

    -- 체크 제약
                               CONSTRAINT chk_payout_positive CHECK (payout_amount > 0)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='지급 원장 (배송기사 건당 단일 요금 - MSA)';


-- ============================================================================
-- 테이블 7: platform_revenue (플랫폼 수익 집계 - 4가지 수익원)
-- ============================================================================
CREATE TABLE platform_revenue (
                                  revenue_id          BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '수익 ID',
                                  settlement_batch_id BIGINT NOT NULL COMMENT '정산 배치 ID',

    -- 4가지 수익원
                                  subscription_revenue     DECIMAL(15,2) DEFAULT 0 COMMENT '1️⃣ 구독료 수익 (병원별 월 정액)',
                                  sales_commission_revenue DECIMAL(15,2) DEFAULT 0 COMMENT '2️⃣ 판매 수수료 수익 (매출의 10~30% 차등)',
                                  delivery_fee_revenue     DECIMAL(15,2) DEFAULT 0 COMMENT '3️⃣ 미구독 병원 배송비 수익 (건당 3,000원)',
                                  storage_fee_revenue      DECIMAL(15,2) DEFAULT 0 COMMENT '4️⃣ 보관비 수익 (개당/일당 200원)',

    -- 총 플랫폼 수익 (자동계산)
                                  total_platform_revenue DECIMAL(15,2) GENERATED ALWAYS AS (
                                      COALESCE(subscription_revenue, 0) +
                                      COALESCE(sales_commission_revenue, 0) +
                                      COALESCE(delivery_fee_revenue, 0) +
                                      COALESCE(storage_fee_revenue, 0)
                                      ) STORED COMMENT '총 플랫폼 수익 = 1️⃣ + 2️⃣ + 3️⃣ + 4️⃣',

    -- 이익 정보
                                  gross_profit      DECIMAL(15,2) NOT NULL DEFAULT 0
                                      COMMENT '매출 총이익 (총수익 - 기사 지급액 합계)',
                                  gross_profit_rate DECIMAL(5,2) GENERATED ALWAYS AS (
                                      CASE WHEN total_platform_revenue > 0
                                               THEN ROUND(gross_profit / total_platform_revenue * 100, 2)
                                           ELSE 0 END
                                      ) STORED COMMENT '매출 총이익률(%)',

                                  operating_profit      DECIMAL(15,2) GENERATED ALWAYS AS (0) STORED
        COMMENT '영업이익 (운영비용 데이터 미반영 - 향후 확장 가능)',
                                  operating_profit_rate DECIMAL(5,2)  GENERATED ALWAYS AS (0) STORED
        COMMENT '영업이익률(%) (운영비용 데이터 미반영)',

                                  net_revenue      DECIMAL(15,2) GENERATED ALWAYS AS (
                                      gross_profit
                                      ) STORED COMMENT '순이익 = 매출총이익 (영업비용 미반영)',
                                  net_revenue_rate DECIMAL(5,2) GENERATED ALWAYS AS (
                                      CASE WHEN total_platform_revenue > 0
                                               THEN ROUND(gross_profit / total_platform_revenue * 100, 2)
                                           ELSE 0 END
                                      ) STORED COMMENT '순이익률(%)',

    -- 메타데이터
                                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',

    -- 내부 FK
                                  FOREIGN KEY (settlement_batch_id)
                                      REFERENCES settlement_batch(settlement_batch_id) ON DELETE RESTRICT,

    -- 인덱스
                                  UNIQUE KEY uk_batch (settlement_batch_id),
                                  INDEX idx_created_at (created_at DESC),
                                  INDEX idx_gross_profit (gross_profit)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='플랫폼 수익 집계 (4가지 수익원 - 구독/미구독 모델)';


-- ============================================================================
-- 테이블 8: vat_summary (부가세 집계)
-- ============================================================================
CREATE TABLE vat_summary (
                             vat_summary_id      BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '부가세 집계 ID',
                             settlement_batch_id BIGINT NOT NULL COMMENT '정산 배치 ID',

    -- 집계 기간
                             period_type  ENUM('MONTHLY', 'QUARTERLY', 'YEARLY') NOT NULL COMMENT '기간 유형',
                             period_start DATE NOT NULL COMMENT '집계 시작일',
                             period_end   DATE NOT NULL COMMENT '집계 종료일',

    -- 부가세
                             total_sales_vat_amount    DECIMAL(15,2) NOT NULL DEFAULT 0 COMMENT '총 매출 부가세',
                             total_purchase_vat_amount DECIMAL(15,2) NOT NULL DEFAULT 0 COMMENT '총 매입 부가세',
                             vat_payable               DECIMAL(15,2) NOT NULL DEFAULT 0 COMMENT '납부할 부가세',

    -- 세금계산서 발행 여부
                             tax_report_generated BOOLEAN DEFAULT FALSE COMMENT '세금계산서 발행 여부',

    -- 메타데이터
                             created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '생성일시',

    -- 내부 FK
                             FOREIGN KEY (settlement_batch_id)
                                 REFERENCES settlement_batch(settlement_batch_id) ON DELETE RESTRICT,

    -- 인덱스
                             INDEX idx_batch (settlement_batch_id),
                             INDEX idx_period (period_start, period_end),
                             INDEX idx_period_type (period_type),
                             INDEX idx_tax_report (tax_report_generated),
                             INDEX idx_created_at (created_at DESC),
                             UNIQUE KEY uk_period (period_type, period_start, period_end),

    -- 체크 제약
                             CONSTRAINT chk_vat_period CHECK (period_end >= period_start),
                             CONSTRAINT chk_vat_calc CHECK (
                                 vat_payable = total_sales_vat_amount - total_purchase_vat_amount
                                 )

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='부가세 집계 (기간별 / 세금계산서 발행 여부)';


-- ============================================================================
-- 테이블 9: settlement_event_log (RabbitMQ 이벤트 로그)
-- ============================================================================
CREATE TABLE settlement_event_log (
                                      event_log_id      BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '이벤트 로그 ID',

    -- 이벤트 기본 정보 (Java Enum → VARCHAR 저장)
                                      event_type        VARCHAR(50) NOT NULL COMMENT '이벤트 타입 (ORDER_PAID, DELIVERY_COMPLETED 등)',
                                      event_source      VARCHAR(50) NOT NULL COMMENT '이벤트 소스 (SHOPPING_SERVICE, DELIVERY_SERVICE 등)',

    -- RabbitMQ 멱등성
                                      rabbitmq_message_id VARCHAR(100) COMMENT 'RabbitMQ Message ID (중복 처리 방지)',

    -- 처리 상태
                                      processing_status ENUM('RECEIVED', 'PROCESSING', 'PROCESSED', 'FAILED', 'RETRY')
        NOT NULL DEFAULT 'RECEIVED' COMMENT '처리 상태',
                                      retry_count       INT DEFAULT 0 COMMENT '재시도 횟수 (최대 3회)',

    -- DLQ
                                      moved_to_dlq BOOLEAN DEFAULT FALSE COMMENT 'Dead Letter Queue 이동 여부 (3회 실패 시)',

    -- 메타데이터
                                      received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '수신 시각',

    -- 인덱스
                                      INDEX idx_event_type (event_type),
                                      INDEX idx_event_source (event_source),
                                      INDEX idx_status (processing_status),
                                      INDEX idx_rabbitmq_message (rabbitmq_message_id),
                                      INDEX idx_received_at (received_at DESC),
                                      INDEX idx_dlq (moved_to_dlq),
                                      INDEX idx_retry (retry_count, processing_status),

    -- 체크 제약
                                      CONSTRAINT chk_retry_limit CHECK (retry_count <= 3)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='RabbitMQ 이벤트 로그 (리트라이 3회 / DLQ 추적)';


-- ============================================================================
-- 테이블 10: sales_ledger_snapshot (매출 원장 스냅샷)
-- ============================================================================
CREATE TABLE sales_ledger_snapshot (
                                       snapshot_id         BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '스냅샷 ID',
                                       sales_ledger_id     BIGINT NOT NULL COMMENT '매출 원장 ID',
                                       settlement_batch_id BIGINT NOT NULL COMMENT '정산 배치 ID',

    -- 거래 키 정보
                                       order_id            VARCHAR(50) NOT NULL COMMENT '주문 ID',
                                       product_id          VARCHAR(50) NOT NULL COMMENT '상품 ID',
                                       hospital_id         VARCHAR(50) NOT NULL COMMENT '병원 ID',

    -- 정산 시점 확정값 (업체 수수료 정책 스냅샷)
                                       price_policy_id              BIGINT        NOT NULL COMMENT '적용된 수수료 정책 ID',
                                       snapshot_sales_price         DECIMAL(10,2) NOT NULL COMMENT '정산 시점 판매가',
                                       snapshot_platform_fee_rate   DECIMAL(5,2)  NOT NULL COMMENT '정산 시점 플랫폼 수수료율(%)',
                                       snapshot_vendor_revenue_rate DECIMAL(5,2)  NOT NULL COMMENT '정산 시점 업체 수익률(%)',
                                       snapshot_fee_policy_type     VARCHAR(20)   NOT NULL COMMENT '정산 시점 수수료 정책 유형',

    -- 정산 시점 확정값 (플랫폼 요금 정책 스냅샷)
                                       fee_policy_id                        BIGINT        NOT NULL COMMENT '적용된 플랫폼 요금 정책 ID',
                                       snapshot_subscription_monthly_fee    DECIMAL(10,2) NOT NULL COMMENT '정산 시점 월 구독료',
                                       snapshot_non_subscriber_delivery_fee DECIMAL(10,2) NOT NULL COMMENT '정산 시점 미구독 배송비',
                                       snapshot_storage_fee_per_unit_per_day DECIMAL(10,2) NOT NULL COMMENT '정산 시점 보관료 단가',

    -- 구독 여부 및 최종 배송비
                                       is_subscribed   BOOLEAN       NOT NULL COMMENT '정산 시점 구독 여부',
                                       delivery_fee    DECIMAL(10,2) NOT NULL COMMENT '최종 적용 배송비',

    -- 메타데이터
                                       snapshot_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '스냅샷 생성 시각',

    -- 인덱스
                                       INDEX idx_sales_ledger (sales_ledger_id),
                                       INDEX idx_batch (settlement_batch_id),
                                       INDEX idx_order (order_id),
                                       INDEX idx_hospital (hospital_id),
                                       UNIQUE KEY uk_ledger (sales_ledger_id)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='매출 원장 스냅샷 (정산 시점 정책 확정값 보존 - 불변성 보장)';


-- ============================================================================
-- 테이블 11: payout_ledger_snapshot (지급 원장 스냅샷)
-- ============================================================================
CREATE TABLE payout_ledger_snapshot (
                                        snapshot_id         BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT '스냅샷 ID',
                                        payout_ledger_id    BIGINT NOT NULL COMMENT '지급 원장 ID',
                                        settlement_batch_id BIGINT NOT NULL COMMENT '정산 배치 ID',

    -- 거래 키 정보
                                        delivery_id VARCHAR(50) NOT NULL COMMENT '배송 ID',
                                        driver_id   VARCHAR(50) NOT NULL COMMENT '기사 ID',

    -- 정산 시점 확정값 (기사 요금 정책 스냅샷)
                                        driver_fee_policy_id   BIGINT        NOT NULL COMMENT '적용된 기사 요금 정책 ID',
                                        snapshot_delivery_fee  DECIMAL(10,2) NOT NULL COMMENT '정산 시점 건당 지급액',
                                        snapshot_payout_amount DECIMAL(10,2) NOT NULL COMMENT '최종 지급액',

    -- 메타데이터
                                        snapshot_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '스냅샷 생성 시각',

    -- 인덱스
                                        INDEX idx_payout_ledger (payout_ledger_id),
                                        INDEX idx_batch (settlement_batch_id),
                                        INDEX idx_driver (driver_id),
                                        INDEX idx_delivery (delivery_id),
                                        UNIQUE KEY uk_payout (payout_ledger_id)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='지급 원장 스냅샷 (정산 시점 기사 요금 확정값 보존 - 불변성 보장)';

-- ============================================================================
-- VIEW 정의
-- ============================================================================

-- 1. 경영 대시보드 KPI 뷰
CREATE OR REPLACE VIEW v_dashboard_kpi AS
SELECT
    sb.settlement_batch_id,
    sb.batch_type,
    sb.target_period_start,
    sb.target_period_end,
    sb.status,
    sb.success_count,
    sb.failed_count,
    sb.hold_count,
    sb.duration_seconds,
    COALESCE(pr.subscription_revenue, 0)     AS subscription_revenue,
    COALESCE(pr.sales_commission_revenue, 0) AS sales_commission_revenue,
    COALESCE(pr.delivery_fee_revenue, 0)     AS delivery_fee_revenue,
    COALESCE(pr.storage_fee_revenue, 0)      AS storage_fee_revenue,
    COALESCE(pr.total_platform_revenue, 0)   AS total_platform_revenue,
    COALESCE(pr.gross_profit, 0)             AS gross_profit,
    COALESCE(pr.gross_profit_rate, 0)        AS gross_profit_rate,
    COALESCE(pr.net_revenue, 0)              AS net_revenue,
    COALESCE(pr.net_revenue_rate, 0)         AS net_revenue_rate,
    sb.created_at
FROM settlement_batch sb
         LEFT JOIN platform_revenue pr ON sb.settlement_batch_id = pr.settlement_batch_id;

-- 2. 배치 실패 병원 목록 뷰 (정산 담당자 화면용)
CREATE OR REPLACE VIEW v_batch_failed_hospitals AS
SELECT
    sl.settlement_batch_id,
    sb.batch_type,
    sb.target_period_start,
    sb.target_period_end,
    sl.hospital_id,
    sl.order_id,
    sl.total_amount,
    sl.fail_reason,
    sl.created_at
FROM sales_ledger sl
         JOIN settlement_batch sb ON sl.settlement_batch_id = sb.settlement_batch_id
WHERE sl.settlement_status = 'CANCELLED'
   OR sl.fail_reason IS NOT NULL
ORDER BY sl.settlement_batch_id DESC, sl.created_at DESC;

-- 3. 배치 성공률 통계 뷰
CREATE OR REPLACE VIEW v_batch_statistics AS
SELECT
    batch_type,
    COUNT(*)                                                               AS total_batches,
    SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END)                 AS success_batches,
    SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END)                    AS failed_batches,
    AVG(duration_seconds)                                                  AS avg_duration_seconds,
    AVG(success_count * 100.0 / NULLIF(total_processed_count, 0))         AS avg_success_rate,
    DATE(created_at)                                                       AS batch_date
FROM settlement_batch
GROUP BY batch_type, DATE(created_at);

-- 4. 고객센터 조회 뷰
CREATE OR REPLACE VIEW v_customer_support AS
SELECT
    sl.hospital_id,
    sl.order_id,
    sl.product_id,
    sl.quantity,
    sl.unit_price,
    sl.total_amount,
    sl.delivery_fee,
    sl.is_subscribed,
    sl.settlement_status,
    sl.created_at AS order_date,
    sb.batch_type,
    sb.target_period_start,
    sb.target_period_end,
    sb.status AS batch_status
FROM sales_ledger sl
         LEFT JOIN settlement_batch sb ON sl.settlement_batch_id = sb.settlement_batch_id
ORDER BY sl.created_at DESC;


-- ============================================================================
-- 변경 이력
-- ============================================================================
-- v11.0 (2026-02-25): 선생님 피드백 반영
--
-- [제거]
--   ❌ is_active (정책 테이블 3개) → 선생님 피드백
--   ❌ created_by (정책 테이블 3개) → 한 명 운영
--   ❌ vendor_cache, product_cache → 선생님 피드백 (Redis or 불필요)
--
-- [수정]
--   ✅ vendor_revenue_rate → GENERATED (100 - platform_fee_rate 자동계산)
--   ✅ sales_ledger: fail_reason VARCHAR(255) 추가 (배치 실패 사유)
--   ✅ platform_revenue: operating_profit/rate GENERATED AS 0
--   ✅ platform_revenue: net_revenue GENERATED AS gross_profit
--   ✅ platform_revenue: net_revenue_rate GENERATED 추가
--   ✅ v_batch_failed_hospitals 뷰 추가 (정산 담당자 실패 병원 조회)
--   ✅ 병원명은 FeignClient API로 실시간 조회 (컬럼 불필요)
--
-- [총 테이블: 11개]
--   1.  platform_fee_policy
--   2.  driver_fee_policy
--   3.  settlement_price_policy
--   4.  settlement_batch
--   5.  sales_ledger
--   6.  payout_ledger
--   7.  platform_revenue
--   8.  vat_summary
--   9.  settlement_event_log
--   10. sales_ledger_snapshot
--   11. payout_ledger_snapshot
-- ============================================================================