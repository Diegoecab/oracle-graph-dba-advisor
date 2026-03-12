# Fraud Graph — Visual Model

## Graph Topology

```mermaid
graph LR
    U((USER)):::v1
    D((DEVICE)):::v2
    C((CARD)):::v3
    P((PERSON)):::v4
    PH((PHONE)):::v5
    BA((BANK_ACCOUNT)):::v6

    U -->|USES_DEVICE| D
    U -->|USES_GUEST_DEVICE| D
    U -->|USES_CARD| C
    U -->|USES_GUEST_CARD| C
    U -->|USES_SMART_ID| U
    U -->|USES_SMART_EMAIL| U
    U -->|VALIDATE_PERSON| P
    U -->|DECLARE_PERSON| P
    U -->|VALIDATE_PHONE| PH
    U -->|DECLARE_PHONE| PH
    U -->|WITHDRAWAL_BANK_ACCOUNT| BA

    classDef v1 fill:#4A90D9,stroke:#2C5F8A,color:#fff,stroke-width:2px
    classDef v2 fill:#E8743B,stroke:#A3522A,color:#fff,stroke-width:2px
    classDef v3 fill:#19A979,stroke:#127956,color:#fff,stroke-width:2px
    classDef v4 fill:#E6564E,stroke:#A3423A,color:#fff,stroke-width:2px
    classDef v5 fill:#9B6FCF,stroke:#6E4F93,color:#fff,stroke-width:2px
    classDef v6 fill:#F2C12E,stroke:#B8921F,color:#333,stroke-width:2px
```

## Cardinality (Scale Factor 1)

| Vertex | Rows | Edge | Rows |
|--------|------|------|------|
| USER | ~50K | USES_DEVICE | ~80K |
| DEVICE | ~30K | USES_CARD | ~60K |
| CARD | ~15K | VALIDATE_PERSON | ~50K |
| PERSON | ~8K | DECLARE_PERSON | ~40K |
| PHONE | ~3K | USES_SMART_ID | ~30K |
| BANK_ACCOUNT | ~2K | Others | ~160K |
