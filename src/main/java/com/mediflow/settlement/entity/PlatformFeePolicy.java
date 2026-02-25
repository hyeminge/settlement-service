package com.mediflow.settlement.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "platform_fee_policy")
@Getter
@NoArgsConstructor
public class PlatformFeePolicy {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "fee_policy_id")
    private Long feePolicyId;

    @Column(name = "subscription_monthly_fee", nullable = false)
    private BigDecimal subscriptionMonthlyFee;

    @Column(name = "non_subscriber_delivery_fee", nullable = false)
    private BigDecimal nonSubscriberDeliveryFee;

    @Column(name = "storage_fee_per_unit_per_day", nullable = false)
    private BigDecimal storageFeePerUnitPerDay;

    @Column(name = "effective_from", nullable = false)
    private LocalDate effectiveFrom;

    @Column(name = "effective_to", nullable = false)
    private LocalDate effectiveTo;

    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}