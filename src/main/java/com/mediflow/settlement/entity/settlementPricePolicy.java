package com.mediflow.settlement.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "settlement_price_policy")
@NoArgsConstructor
@Getter
public class settlementPricePolicy {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "price_policy_id")
    private Long pricePolicyId;

    // 상품 아이디 (쇼핑몰 참조)
    @Column(name = "product_id", nullable = false)
    private String productId;

    // 위탁업체 아이디 (쇼핑몰 참조)
    @Column(name = "vendor_id", nullable = false)
    private String vendorId;

    // 판매가
    @Column(name = "sales_price", nullable = false)
    private BigDecimal salesPrice;

    // 플랫폼 수수료율
    @Column(name = "platform_fee_rate", nullable = false)
    private BigDecimal platformFeeRate;

    // 업체 수수료율
    @Column(name = "vendor_revenue_rate", insertable = false, updatable = false)
    private BigDecimal vendorRevenueRate;

    // 수수료 정책
    @Enumerated(EnumType.STRING)
    @Column(name = "fee_policy_type")
    private FeePolicyType feePolicyType;

    // 적용 시작일
    @Column(name = "effective_from", nullable = false)
    private LocalDate effectiveFrom;

    // 적용 종료일
    @Column(name = "effective_to", nullable = false)
    private LocalDate effectiveTo;

    // 생성일시
    @Column(name = "created_at", insertable = false, updatable = false)
    private LocalDateTime createdAt;

}


