# 🧩 Deck変換コマンド一覧（M01〜M08）

本メモは、保健一問一答アプリ用の **CSV → JSON変換コマンド** 一覧です。  
各デッキ（M01〜M08）を `tools/convert_csv_to_json.py` で変換する際に使用します。
すべてのcommandはrepository rootの`apps/health`directoryから実行してください。

---

## 共通設定

- 出力先：`assets/decks`
- 無料出題比率：`--free_ratio 0.2`

---

## M01：現代社会と健康（上）

```bash
python3 tools/convert_csv_to_json.py \
  --deck_id deck_M01 \
  --deck_title "現代社会と健康（上）" \
  --units "unit_health_concepts:健康の考え方と成り立ち:assets_src/csv/unit_health_concepts.csv,unit_health_status:私たちの健康のすがた:assets_src/csv/unit_health_status.csv,unit_lifestyle_disease_prevention:生活習慣病の予防と回復:assets_src/csv/unit_lifestyle_disease_prevention.csv,unit_cancer_causes_and_prevention:がんの原因と予防:assets_src/csv/unit_cancer_causes_and_prevention.csv,unit_cancer_treatment_and_recovery:がんの治療と回復:assets_src/csv/unit_cancer_treatment_and_recovery.csv,unit_physical_activity_and_health:運動と健康:assets_src/csv/unit_physical_activity_and_health.csv" \
  --outdir assets/decks \
  --free_ratio 0.2

M02：現代社会と健康（中）
python3 tools/convert_csv_to_json.py \
  --deck_id deck_M02 \
  --deck_title "現代社会と健康（中）" \
  --units "unit_nutrition_and_health:食事と健康:assets_src/csv/unit_nutrition_and_health.csv,unit_rest_and_sleep_health:休養・睡眠と健康:assets_src/csv/unit_rest_and_sleep_health.csv,unit_smoking_and_health:喫煙と健康:assets_src/csv/unit_smoking_and_health.csv,unit_alcohol_and_health:飲酒と健康:assets_src/csv/unit_alcohol_and_health.csv,unit_drug_abuse_and_health:薬物乱用と健康:assets_src/csv/unit_drug_abuse_and_health.csv,unit_mental_disorders_features:精神疾患の特徴:assets_src/csv/unit_mental_disorders_features.csv" \
  --outdir assets/decks \
  --free_ratio 0.2

M03：現代社会と健康（下）
python3 tools/convert_csv_to_json.py \
  --deck_id deck_M03 \
  --deck_title "現代社会と健康（下）" \
  --units "unit_mental_disorders_prevention:精神疾患の予防:assets_src/csv/unit_mental_disorders_prevention.csv,unit_mental_disorders_recovery:精神疾患からの回復:assets_src/csv/unit_mental_disorders_recovery.csv,unit_modern_infectious_diseases:現代の感染症:assets_src/csv/unit_modern_infectious_diseases.csv,unit_infectious_disease_prevention:感染症の予防:assets_src/csv/unit_infectious_disease_prevention.csv,unit_sti_and_hiv_prevention:性感染症・エイズとその予防:assets_src/csv/unit_sti_and_hiv_prevention.csv,unit_health_decision_making:健康に関する意思決定・行動選択:assets_src/csv/unit_health_decision_making.csv,unit_health_environment:健康に関する環境づくり:assets_src/csv/unit_health_environment.csv" \
  --outdir assets/decks \
  --free_ratio 0.2

M04：安全な社会生活
python3 tools/convert_csv_to_json.py \
  --deck_id deck_M04 \
  --deck_title "安全な社会生活" \
  --units "unit_accident_overview_and_factors:事故の現状と発生要因:assets_src/csv/unit_accident_overview_and_factors.csv,unit_safe_society_development:安全な社会の形成:assets_src/csv/unit_safe_society_development.csv,unit_traffic_safety:交通における安全:assets_src/csv/unit_traffic_safety.csv,unit_first_aid_basics:応急手当の意義とその基本:assets_src/csv/unit_first_aid_basics.csv,unit_everyday_first_aid:日常的な応急手当:assets_src/csv/unit_everyday_first_aid.csv,unit_cardiopulmonary_resuscitation:心肺蘇生法:assets_src/csv/unit_cardiopulmonary_resuscitation.csv" \
  --outdir assets/decks \
  --free_ratio 0.2

M05：生涯を通じる健康（前半）
python3 tools/convert_csv_to_json.py \
  --deck_id deck_M05 \
  --deck_title "生涯を通じる健康（前半）" \
  --units "unit_life_stages_and_health:ライフステージと健康:assets_src/csv/unit_life_stages_and_health.csv,unit_adolescence_and_health:思春期と健康:assets_src/csv/unit_adolescence_and_health.csv,unit_sexual_attitudes_and_behavior:性意識と性行動の選択:assets_src/csv/unit_sexual_attitudes_and_behavior.csv,unit_pregnancy_childbirth_and_health:妊娠・出産と健康:assets_src/csv/unit_pregnancy_childbirth_and_health.csv,unit_contraception_and_induced_abortion:避妊法と人工妊娠中絶:assets_src/csv/unit_contraception_and_induced_abortion.csv" \
  --outdir assets/decks \
  --free_ratio 0.2

M06：生涯を通じる健康（後半）
python3 tools/convert_csv_to_json.py \
  --deck_id deck_M06 \
  --deck_title "生涯を通じる健康（後半）" \
  --units "unit_marriage_and_health:結婚生活と健康:assets_src/csv/unit_marriage_and_health.csv,unit_middle_and_older_adulthood_health:中高年期と健康:assets_src/csv/unit_middle_and_older_adulthood_health.csv,unit_work_and_health:働くことと健康:assets_src/csv/unit_work_and_health.csv,unit_occupational_accidents_and_health:労働災害と健康:assets_src/csv/unit_occupational_accidents_and_health.csv,unit_healthy_work_life:健康的な職業生活:assets_src/csv/unit_healthy_work_life.csv" \
  --outdir assets/decks \
  --free_ratio 0.2

M07：健康を支える環境づくり（前半）
python3 tools/convert_csv_to_json.py \
  --deck_id deck_M07 \
  --deck_title "健康を支える環境づくり（前半）" \
  --units "unit_air_pollution_and_health:大気汚染と健康:assets_src/csv/unit_air_pollution_and_health.csv,unit_water_and_soil_pollution_and_health:水質汚濁、土壌汚染と健康:assets_src/csv/unit_water_and_soil_pollution_and_health.csv,unit_environment_and_health_measures:環境と健康にかかわる対策:assets_src/csv/unit_environment_and_health_measures.csv,unit_waste_management_and_water_infrastructure:ごみの処理と上下水道の整備:assets_src/csv/unit_waste_management_and_water_infrastructure.csv,unit_food_safety:食品の安全性:assets_src/csv/unit_food_safety.csv,unit_food_hygiene_activities:食品衛生にかかわる活動:assets_src/csv/unit_food_hygiene_activities.csv" \
  --outdir assets/decks \
  --free_ratio 0.2

M08：健康を支える環境づくり（後半）
python3 tools/convert_csv_to_json.py \
  --deck_id deck_M08 \
  --deck_title "健康を支える環境づくり（後半）" \
  --units "unit_public_health_services:保健サービスとその活用:assets_src/csv/unit_public_health_services.csv,unit_medical_services_and_use:医療サービスとその活用:assets_src/csv/unit_medical_services_and_use.csv,unit_pharmaceutical_system_and_use:医薬品の制度とその活用:assets_src/csv/unit_pharmaceutical_system_and_use.csv,unit_health_activities_and_social_measures:さまざまな保健活動や社会的対策:assets_src/csv/unit_health_activities_and_social_measures.csv,unit_health_environment_and_social_participation:健康に関する環境づくりと社会参加:assets_src/csv/unit_health_environment_and_social_participation.csv" \
  --outdir assets/decks \
  --free_ratio 0.2


✅ 出力ファイル：

assets/decks/deck_M01.json
assets/decks/deck_M02.json
assets/decks/deck_M03.json
assets/decks/deck_M04.json
assets/decks/deck_M05.json
assets/decks/deck_M06.json
assets/decks/deck_M07.json
assets/decks/deck_M08.json

📄 保存先推奨
docs/deck_conversion_commands.md

💡 このメモをもとに、ターミナルで各コマンドを1つずつ実行すると
すべてのデッキJSONを自動生成できます。
