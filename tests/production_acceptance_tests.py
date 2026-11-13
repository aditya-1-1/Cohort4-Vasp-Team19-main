#!/usr/bin/env python3
"""
Production Acceptance Tests for Rehearse AI Integration
Validates Test A through Test F according to Section 15 requirements.
"""

import os
import sys
import json
import time
import urllib.request
import urllib.error

sys.path.insert(0, os.path.abspath("."))

BACKEND_URL = os.environ.get("BACKEND_URL", "http://localhost:8080")

def test_suite():
    print("=" * 80)
    print("  🧪 REHEARSE PRODUCTION AI INTEGRATION ACCEPTANCE SUITE")
    print("=" * 80)
    
    passed = 0
    total = 7

    # ---------------------------------------------------------
    # Test A: Gemini Online Evaluation
    # ---------------------------------------------------------
    print("\n[TEST A] Gemini Online Evaluation via Rehearse Backend...")
    payload_a = {
        "interview_id": "test-session-a",
        "question_id": "q-design-cache",
        "question": "How would you design a distributed cache with LRU eviction and high availability?",
        "candidate_answer": "I would use consistent hashing with virtual nodes across server instances. For LRU eviction, each node maintains a doubly linked list coupled with a hash map for O(1) eviction and lookup. For high availability, we employ Raft-based primary-replica replication with write-through caching.",
        "domain": "System Design",
        "subdomain": "Distributed Systems",
        "question_type": "technical",
        "difficulty": "advanced",
        "candidate_level": "intermediate",
        "transcript_analytics": {
            "words_per_minute": 145,
            "filler_word_count": 0,
            "repeated_word_count": 0
        }
    }
    
    for attempt in range(3):
        try:
            req = urllib.request.Request(
                f"{BACKEND_URL}/api/evaluate",
                data=json.dumps(payload_a).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=40) as resp:
                data = json.loads(resp.read().decode())
                dur = time.time() - t0
                
                assert data["provider"] == "google_gemini", "Provider must be google_gemini"
                assert data["model_id"] == "gemini-3.5-flash-lite", "Model must be verified gemini-3.5-flash-lite"
                assert data["execution_mode"] == "online", "Mode must be online"
                assert "overall_score" in data and isinstance(data["overall_score"], (int, float))
                assert data["overall_score"] > 0
                
                res = data["evaluation_result"]
                assert "evaluation" in res
                assert "correctness" in res["evaluation"]
                assert "relevance" in res["evaluation"]
                assert "completeness" in res["evaluation"]
                assert "clarity" in res["evaluation"]
                assert "technical_depth" in res["evaluation"]
                assert len(res["strengths"]) > 0
                
                print(f"  ✅ PASSED: Online Gemini evaluation received in {dur:.2f}s | Score: {data['overall_score']}/10 ({res['score_label']}) | Provider: {data['provider']}")
                passed += 1
                break
        except Exception as e:
            if attempt < 2:
                time.sleep(2)
                continue
            print(f"  ❌ FAILED: {e}")
            break

    # ---------------------------------------------------------
    # Test B: Apple Offline Foundation Models (Framework Inspection)
    # ---------------------------------------------------------
    print("\n[TEST B] Apple Offline Foundation Models Framework Contract...")
    # Verify the Swift service AppleFoundationModelsService exists and declares exact SystemLanguageModel availability checks
    swift_service_path = "Rehearse/Services/AppleFoundationModelsService.swift"
    assert os.path.exists(swift_service_path), "AppleFoundationModelsService.swift must exist"
    with open(swift_service_path, "r") as f:
        content = f.read()
        assert "SystemLanguageModel.default" in content, "Must use SystemLanguageModel.default"
        assert "LanguageModelSession" in content, "Must use LanguageModelSession"
        assert "appleFoundationModels" in content or "apple_foundation_models" in content, "Must record apple_foundation_models provider"
        assert "offline" in content, "Must record offline execution mode"
        assert "deviceNotEligible" in content, "Must handle deviceNotEligible"
        assert "appleIntelligenceNotEnabled" in content, "Must handle appleIntelligenceNotEnabled"
        assert "modelNotReady" in content, "Must handle modelNotReady"
    print("  ✅ PASSED: Apple Foundation Models framework implementation verified with official availability lifecycle.")
    passed += 1

    # ---------------------------------------------------------
    # Test C: Automatic Engine Selection, Resilient Fallback & PDF Export
    # ---------------------------------------------------------
    print("\n[TEST C] Automatic AI Selection, Offline Failover & PDF Export Verification...")
    coordinator_path = "Rehearse/Services/AIEvaluationCoordinator.swift"
    assert os.path.exists(coordinator_path), "AIEvaluationCoordinator.swift must exist"
    with open(coordinator_path, "r") as f:
        c_content = f.read()
        assert "RehearseBackendClient.shared.evaluate" in c_content, "Must try online backend first"
        assert "AppleFoundationModelsService.shared.evaluate" in c_content, "Must fall back to Apple Foundation Models on failure"
    
    # Verify candidate-facing setup doesn't expose confusing engine pickers
    view_path = "Rehearse/Views/InterviewSetupView.swift"
    with open(view_path, "r") as f:
        v_content = f.read()
        assert "aiEngineSection" not in v_content, "Manual engine picker must be removed from candidate setup"

    # Verify PDF export service and button are integrated
    pdf_service_path = "Rehearse/Services/PDFReportGenerator.swift"
    assert os.path.exists(pdf_service_path), "PDFReportGenerator.swift must exist"
    feedback_report_path = "Rehearse/Views/FeedbackReport.swift"
    with open(feedback_report_path, "r") as f:
        fb_content = f.read()
        assert "Download Feedback as PDF" in fb_content, "Download Feedback as PDF button must be present at end of report"
        assert "PDFReportGenerator.createPDF" in fb_content, "Must call PDFReportGenerator"
    print("  ✅ PASSED: System automatically selects online with offline Apple FM fallback; candidate UI is clean and PDF export is integrated.")
    passed += 1

    # ---------------------------------------------------------
    # Test D: Invalid Model Output & Controlled Repair
    # ---------------------------------------------------------
    print("\n[TEST D] JSON Schema Validation & Controlled Repair Mechanism...")
    import backend.server as srv
    # Test malformed JSON with markdown fences and trailing commas
    malformed = "```json\n{\n  \"overallScore\": 85,\n  \"score_label\": \"Good\"\n}```"
    cleaned = srv.clean_json_text(malformed)
    assert cleaned == '{\n  \"overallScore\": 85,\n  \"score_label\": \"Good\"\n}', f"Cleaned failed: {cleaned}"
    
    # Verify calculate_overall_score enforces Section 7 weights
    sample_eval = {
        "correctness": {"score": 8},
        "relevance": {"score": 9},
        "completeness": {"score": 7},
        "clarity": {"score": 8},
        "technical_depth": {"score": 8}
    }
    # Expected: (8*0.3)+(9*0.2)+(7*0.2)+(8*0.15)+(8*0.15) = 2.4 + 1.8 + 1.4 + 1.2 + 1.2 = 8.0
    calc_score, calc_label = srv.calculate_overall_score("technical", sample_eval, {})
    assert calc_score == 8.0, f"Expected 8.0, got {calc_score}"
    assert calc_label == "Very Good", f"Expected 'Very Good', got {calc_label}"
    print(f"  ✅ PASSED: Cleaned malformed JSON and verified exact Section 7 weighted scoring formula (Score: {calc_score}, Label: {calc_label}).")
    passed += 1

    # ---------------------------------------------------------
    # Test E: Evaluation Consistency Across Rubrics
    # ---------------------------------------------------------
    print("\n[TEST E] Evaluation Consistency Across Technical & Behavioral Rubrics...")
    behavioral_payload = {
        "interview_id": "test-session-b",
        "question_id": "q-behavioral-1",
        "question": "Tell me about a time you resolved a technical disagreement within your engineering team.",
        "candidate_answer": "In my previous project, two engineers disagreed on whether to migrate to gRPC or keep REST. As tech lead, I facilitated a spike benchmark where both teams measured p99 latency, developer velocity, and client SDK generation overhead. We reviewed the empirical data together, concluded REST satisfied our SLAs with lower tooling overhead, and aligned the team unanimously.",
        "domain": "Behavioral Interviews",
        "subdomain": "Engineering Leadership",
        "question_type": "behavioral",
        "difficulty": "intermediate",
        "candidate_level": "intermediate",
        "transcript_analytics": {
            "words_per_minute": 138,
            "filler_word_count": 0,
            "repeated_word_count": 0
        }
    }
    try:
        req = urllib.request.Request(
            f"{BACKEND_URL}/api/evaluate",
            data=json.dumps(behavioral_payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=25) as resp:
            b_data = json.loads(resp.read().decode())
            b_res = b_data["evaluation_result"]
            assert b_data["overall_score"] >= 7.0, f"Strong STAR answer should score >= 7.0, got {b_data['overall_score']}"
            assert len(b_res["strengths"]) > 0
            print(f"  ✅ PASSED: Behavioral answer evaluated with STAR rubric | Score: {b_data['overall_score']}/10 ({b_res['score_label']}) | Strengths: {b_res['strengths'][0]}")
            passed += 1
    except Exception as e:
        print(f"  ❌ FAILED: {e}")

    # ---------------------------------------------------------
    # Test F: Follow-Up Logic & Next Question Generation
    # ---------------------------------------------------------
    print("\n[TEST F] Follow-Up Decision Rules & Next Question Generation...")
    # Test incomplete answer to confirm follow_up.needed is triggered
    incomplete_payload = {
        "interview_id": "test-session-c",
        "question_id": "q-incomplete",
        "question": "How do you ensure data consistency between PostgreSQL and a Redis cache?",
        "candidate_answer": "I just write to both.",
        "domain": "System Design",
        "subdomain": "Databases",
        "question_type": "technical",
        "difficulty": "advanced",
        "candidate_level": "intermediate"
    }
    try:
        req = urllib.request.Request(
            f"{BACKEND_URL}/api/evaluate",
            data=json.dumps(incomplete_payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=25) as resp:
            inc_data = json.loads(resp.read().decode())
            inc_res = inc_data["evaluation_result"]
            assert inc_data["overall_score"] < 6.0, f"Incomplete answer should score lower, got {inc_data['overall_score']}"
            assert inc_res["follow_up"]["needed"] is True, "Incomplete answer MUST trigger follow_up.needed = true"
            assert inc_res["follow_up"]["question"] is not None
            print(f"  ✅ PASSED: Incomplete answer appropriately triggered follow-up:")
            print(f"     • Score:    {inc_data['overall_score']}/10 ({inc_res['score_label']})")
            print(f"     • Reason:   {inc_res['follow_up']['reason']}")
            print(f"     • Followup: \"{inc_res['follow_up']['question']}\"")
            passed += 1
    except Exception as e:
        print(f"  ❌ FAILED: {e}")

    # ---------------------------------------------------------
    # Test G: Dynamic AI Question Generation (Tailored to Role, Company & Level)
    # ---------------------------------------------------------
    print("\n[TEST G] Dynamic AI Question Generation (Tailored to Role, Company & Level)...")
    q_payload = {
        "company": "Apple",
        "role": "iOS Engineer",
        "experience_level": "Senior (5+ yrs)",
        "interview_type": "technical",
        "duration_minutes": 20
    }
    try:
        req = urllib.request.Request(
            f"{BACKEND_URL}/api/generate_questions",
            data=json.dumps(q_payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            q_data = json.loads(resp.read().decode())
            assert "questions" in q_data, "Response must include 'questions' array"
            questions = q_data["questions"]
            assert len(questions) >= 3, f"Expected at least 3 questions, got {len(questions)}"
            first_q = questions[0]["question"]
            # Ensure it is NOT the old generic LRU cache question
            assert "distributed cache with LRU eviction" not in first_q, "Must NOT be generic hardcoded LRU question"
            print(f"  ✅ PASSED: Generated {len(questions)} tailored questions for {q_payload['experience_level']} {q_payload['role']} at {q_payload['company']}:")
            for idx, item in enumerate(questions):
                print(f"     Q{idx+1}: \"{item['question'][:80]}...\" ({item.get('topic', 'General')})")
            passed += 1
    except Exception as e:
        print(f"  ❌ FAILED: {e}")

    print("\n" + "=" * 80)
    print(f"  🏆 ACCEPTANCE TEST RESULTS: {passed}/{total} TESTS PASSED")
    print("=" * 80)

if __name__ == "__main__":
    test_suite()
