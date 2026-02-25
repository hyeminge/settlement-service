package com.mediflow.settlement.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "driver_fee_policy")
@NoArgsConstructor
@Getter
public class DriverFeePolicy {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "driver_fee_policy_id")
    private Long driverFeePolicyId;

    // 배송 건당 기사 지급액
    @Column(name = "delivery_fee", nullable = false)
    private BigDecimal deliveryFee;

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
