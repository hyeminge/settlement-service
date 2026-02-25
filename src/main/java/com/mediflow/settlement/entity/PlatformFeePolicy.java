package com.mediflow.settlement.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "platform_fee_policy")
@NoArgsConstructor  // JPA를 위한 기본 생성자
@Getter
public class PlatformFeePolicy {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "fee_policy_id")
    private Long feePolicyId;

    // 월 구독료
    @Column(name = "subscription_monthly_fee", nullable = false)
    private BigDecimal subscriptionMonthlyFee;

    // 미구독 병원 건당 배송비
    @Column(name = "non_subscriber_delivery_fee", nullable = false)
    private BigDecimal nonSubscriberDeliveryFee;

    // 보관료 (개당/일당)
    @Column(name = "storage_fee_per_unit_per_day", nullable = false)
    private BigDecimal storageFeePerUnitPerDay;

    // 정책 적용 시작일
    @Column(name = "effective_from", nullable = false)
    private LocalDate effectiveFrom;

    // 정책 적용 종료일
    @Column(name = "effective_to", nullable = false)
    private LocalDate effectiveTo;

    // DB DEFAULT CURRENT_TIMESTAMP 사용 (삽입/수정 불가)
    @Column(name = "created_at", insertable = false, updatable = false)
    private LocalDateTime createdAt;
}
// test