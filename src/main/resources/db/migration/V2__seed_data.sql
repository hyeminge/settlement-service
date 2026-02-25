-- ============================================================================
-- 초기 데이터
-- ============================================================================

-- 플랫폼 요금 정책
INSERT INTO platform_fee_policy
(subscription_monthly_fee, non_subscriber_delivery_fee, storage_fee_per_unit_per_day,
 effective_from, effective_to)
VALUES
    (297000, 3000, 200, '2026-01-01', '2026-12-31');

-- 기사 지급 정책
INSERT INTO driver_fee_policy
(delivery_fee, effective_from, effective_to)
VALUES
    (3000, '2026-01-01', '2026-12-31');

-- 업체 수수료 정책
-- vendor_revenue_rate는 GENERATED이므로 생략
INSERT INTO settlement_price_policy
(policy_version, product_id, vendor_id, sales_price,
 platform_fee_rate, fee_policy_type,
 effective_from, effective_to)
VALUES
    (1, 'PROD-001', 'VENDOR-A', 10000.00, 20.00, 'STANDARD', '2026-01-01', '2026-12-31'),
    (1, 'PROD-002', 'VENDOR-B',  7000.00, 20.00, 'STANDARD', '2026-01-01', '2026-12-31'),
    (1, 'PROD-003', 'VENDOR-C', 15000.00, 10.00, 'VIP',      '2026-01-01', '2026-12-31'),
    (1, 'PROD-004', 'VENDOR-D', 22000.00, 10.00, 'VIP',      '2026-01-15', '2026-06-30'),
    (1, 'PROD-005', 'VENDOR-E',  5000.00, 30.00, 'NEW',      '2026-02-01', '2026-12-31');
