#!/usr/bin/env python3
"""
Rehearse AI Backend Server
Handles online interview evaluation powered by Google Gemini (Flash-Lite).
Implements the shared Master Evaluation System Prompt, JSON schema validation,
programmatic Section 7 scoring, controlled single-repair attempts, and metadata packaging.
"""

import os
import sys
import json
import time
import re
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timezone

# Configuration
PORT = int(os.environ.get("PORT", "8080"))
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "").strip()

# Default model verified via Google AI Studio v1beta API: gemini-3.5-flash-lite
DEFAULT_MODEL = "gemini-3.5-flash-lite"
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL

# Load from .env if present
env_path = os.path.join(os.path.dirname(__file__), ".env")
if os.path.exists(env_path):
    with open(env_path, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip().strip('"').strip("'")
                if k == "GEMINI_API_KEY" and not GEMINI_API_KEY:
                    GEMINI_API_KEY = v
                elif k == "GEMINI_MODEL" and os.environ.get("GEMINI_MODEL") is None:
                    GEMINI_MODEL = v

SCHEMA_VERSION = "1.0"

MASTER_SYSTEM_PROMPT = """You are Rehearse, a professional AI interview evaluator and interview coach.
Your responsibility is to evaluate a candidate's answer to an interview question objectively, consistently, and fairly.
You are not a generic chatbot.
You must evaluate the answer against the actual question, interview domain, difficulty, expected knowledge level, and available context.

Your primary objectives are:
1. Assess the technical or behavioral quality of the answer.
2. Identify what the candidate understood correctly.
3. Identify missing, incorrect, vague, or irrelevant information.
4. Measure communication quality.
5. Give specific and actionable feedback.
6. Determine whether a follow-up question is necessary.
7. Provide the next appropriate interview question.

Never fabricate candidate achievements, technical details, or evidence.
Never award high scores simply because an answer is long or confidently written.
Never penalize a concise answer if it completely addresses the question.

SUPPORTED INTERVIEW DOMAINS:
1. Computer Science Fundamentals
2. Artificial Intelligence and Machine Learning
3. Data Science and Data Analytics
4. Software Development and Engineering
5. System Design
6. Behavioral Interviews (STAR framework)
7. Project-Based Interviews

EVALUATION CRITERIA (0 to 10 scale for each):
Technical Rubric:
- correctness: factually/technically correct (0-10)
- relevance: directly answers actual question (0-10)
- completeness: covers necessary concepts (0-10)
- clarity: understandable and logically organized (0-10)
- technical_depth: depth of mechanisms and trade-offs relative to level (0-10)

Additional Rubric (when applicable: project_depth, problem_solving, or behavioral):
- project_depth: concept, completion, application, terminology, ownership (each 0-10)
- problem_solving: problem_understanding, approach, logical_reasoning, trade_offs (each 0-10)
- behavioral: situation_and_context, personal_contribution, actions_and_reasoning, outcome_and_learning (each 0-10)

Communication:
- clarity (0-10), structure (0-10), conciseness (0-10).
- Keep filler_word_count, words_per_minute, repeated_word_count as null unless provided in transcript analytics.

FOLLOW-UP QUESTION RULES:
- Set follow_up.needed to true only when a follow-up would meaningfully improve assessment (e.g. unclear technical claim, incomplete mechanism, vague project ownership).
- If answer is complete or demonstrates expected knowledge, set needed: false, question: null.

NEXT QUESTION RULES:
- Provide next interview question appropriate to domain, difficulty, and progression.
- If follow-up is needed, do not advance to unrelated new topic. If interview complete, return null.

REASONING AND EVALUATION DEPTH:
- Evaluate with the technical depth and analytical discernment of a Senior/Staff Engineering Interviewer.
- Thoroughly dissect mechanisms, failure modes, data consistency guarantees, concurrency race conditions, memory implications, and architectural tradeoffs.
- In `feedback.what_went_well`: Cite exact architectural components, metrics, and principles the candidate explained correctly.
- In `feedback.what_to_improve`: Provide specific, in-depth architectural critiques detailing what edge cases, scalability limits, or operational failure modes were omitted.
- In `feedback.ideal_answer_guidance`: Provide an exemplary, gold-standard answer demonstrating how an expert would structure the solution with concrete metrics and clear tradeoffs.
- In `strengths` and `weaknesses`: Give sharp, concrete observations grounded directly in the candidate's actual words rather than generic placeholders.

OUTPUT STRICT FORMAT:
Return pure valid JSON matching this schema exactly. No Markdown, no code fences, no introductory or concluding text:
{
  "schema_version": "1.0",
  "question_id": "string",
  "question_type": "technical | behavioral | project_based | problem_solving | system_design",
  "domain": "string",
  "subdomain": "string",
  "difficulty": "beginner | intermediate | advanced",
  "overall_score": 0.0,
  "score_label": "string",
  "evaluation": {
    "correctness": { "score": 0, "feedback": "string" },
    "relevance": { "score": 0, "feedback": "string" },
    "completeness": { "score": 0, "feedback": "string" },
    "clarity": { "score": 0, "feedback": "string" },
    "technical_depth": { "score": 0, "feedback": "string" }
  },
  "additional_rubric": {
    "rubric_type": "none | project_depth | problem_solving | behavioral",
    "criteria": [
      { "name": "string", "score": 0, "feedback": "string" }
    ]
  },
  "communication": {
    "clarity": 0,
    "structure": 0,
    "conciseness": 0,
    "filler_word_count": null,
    "words_per_minute": null,
    "repeated_word_count": null,
    "notes": "string"
  },
  "strengths": ["string"],
  "weaknesses": ["string"],
  "missing_concepts": ["string"],
  "feedback": {
    "summary": "string",
    "what_went_well": "string",
    "what_to_improve": "string",
    "ideal_answer_guidance": "string"
  },
  "follow_up": {
    "needed": false,
    "reason": null,
    "question": null,
    "tests": null
  },
  "next_question": {
    "question": "string or null",
    "domain": "string or null",
    "difficulty": "string or null",
    "reason": "string or null"
  }
}
"""

def safe_float(val, default=6.0):
    """Safely parse a score float."""
    try:
        return float(val)
    except (ValueError, TypeError):
        return default

def calculate_overall_score(q_type, eval_dict, additional_rubric):
    """
    Programmatic calculation of overall score following Section 7 weights.
    Returns (score_out_of_10, score_label).
    """
    q_type_clean = (q_type or "").lower().replace("-", "_").replace(" ", "_")
    score = 0.0

    # Extract criteria map safely from additional_rubric
    crit_map = {}
    if isinstance(additional_rubric, dict):
        raw_crit = additional_rubric.get("criteria", [])
        if isinstance(raw_crit, list):
            for c in raw_crit:
                if isinstance(c, dict):
                    name = str(c.get("name", "")).lower().replace(" ", "_").replace("-", "_")
                    crit_map[name] = safe_float(c.get("score", 6.0))
        elif isinstance(raw_crit, dict):
            for k, v in raw_crit.items():
                name = str(k).lower().replace(" ", "_").replace("-", "_")
                if isinstance(v, dict):
                    crit_map[name] = safe_float(v.get("score", 6.0))
                else:
                    crit_map[name] = safe_float(v)
    elif isinstance(additional_rubric, list):
        for c in additional_rubric:
            if isinstance(c, dict):
                name = str(c.get("name", "")).lower().replace(" ", "_").replace("-", "_")
                crit_map[name] = safe_float(c.get("score", 6.0))

    if q_type_clean == "behavioral":
        sit = crit_map.get("situation_and_context", crit_map.get("situation", 6.0))
        contrib = crit_map.get("personal_contribution", crit_map.get("contribution", 6.0))
        act = crit_map.get("actions_and_reasoning", crit_map.get("actions", 6.0))
        out = crit_map.get("outcome_and_learning", crit_map.get("outcome", 6.0))
        
        # If crit_map had none of the STAR keys, fall back to general eval_dict if present
        if not crit_map and isinstance(eval_dict, dict) and eval_dict:
            c = safe_float(eval_dict.get("correctness", {}).get("score", 6))
            r = safe_float(eval_dict.get("relevance", {}).get("score", 6))
            comp = safe_float(eval_dict.get("completeness", {}).get("score", 6))
            cl = safe_float(eval_dict.get("clarity", {}).get("score", 6))
            d = safe_float(eval_dict.get("technical_depth", {}).get("score", 6))
            score = (c * 0.30) + (r * 0.20) + (comp * 0.20) + (cl * 0.15) + (d * 0.15)
        else:
            score = (sit * 0.20) + (contrib * 0.25) + (act * 0.30) + (out * 0.25)

    elif q_type_clean in ["project_based", "project"]:
        concept = crit_map.get("concept", 6.0)
        completion = crit_map.get("completion", 6.0)
        app = crit_map.get("application", 6.0)
        terminology = crit_map.get("terminology", 6.0)
        ownership = crit_map.get("ownership", 6.0)
        claims = crit_map.get("technical_correctness_of_claims", crit_map.get("claims", 6.0))
        if not crit_map and isinstance(eval_dict, dict) and eval_dict:
            c = safe_float(eval_dict.get("correctness", {}).get("score", 6))
            r = safe_float(eval_dict.get("relevance", {}).get("score", 6))
            comp = safe_float(eval_dict.get("completeness", {}).get("score", 6))
            cl = safe_float(eval_dict.get("clarity", {}).get("score", 6))
            d = safe_float(eval_dict.get("technical_depth", {}).get("score", 6))
            score = (c * 0.30) + (r * 0.20) + (comp * 0.20) + (cl * 0.15) + (d * 0.15)
        else:
            score = (concept * 0.15) + (completion * 0.15) + (app * 0.25) + (terminology * 0.10) + (ownership * 0.20) + (claims * 0.15)

    elif q_type_clean in ["problem_solving", "algorithmic"]:
        understanding = crit_map.get("problem_understanding", crit_map.get("understanding", 6.0))
        approach = crit_map.get("approach", 6.0)
        logic = crit_map.get("logical_reasoning", crit_map.get("reasoning", 6.0))
        trade_offs = crit_map.get("trade_offs", crit_map.get("tradeoffs", 6.0))
        if not crit_map and isinstance(eval_dict, dict) and eval_dict:
            c = safe_float(eval_dict.get("correctness", {}).get("score", 6))
            r = safe_float(eval_dict.get("relevance", {}).get("score", 6))
            comp = safe_float(eval_dict.get("completeness", {}).get("score", 6))
            cl = safe_float(eval_dict.get("clarity", {}).get("score", 6))
            d = safe_float(eval_dict.get("technical_depth", {}).get("score", 6))
            score = (c * 0.30) + (r * 0.20) + (comp * 0.20) + (cl * 0.15) + (d * 0.15)
        else:
            score = (understanding * 0.20) + (approach * 0.30) + (logic * 0.30) + (trade_offs * 0.20)

    else:
        # Technical / System Design
        c = safe_float(eval_dict.get("correctness", {}).get("score", 6) if isinstance(eval_dict, dict) else 6)
        r = safe_float(eval_dict.get("relevance", {}).get("score", 6) if isinstance(eval_dict, dict) else 6)
        comp = safe_float(eval_dict.get("completeness", {}).get("score", 6) if isinstance(eval_dict, dict) else 6)
        cl = safe_float(eval_dict.get("clarity", {}).get("score", 6) if isinstance(eval_dict, dict) else 6)
        d = safe_float(eval_dict.get("technical_depth", {}).get("score", 6) if isinstance(eval_dict, dict) else 6)
        score = (c * 0.30) + (r * 0.20) + (comp * 0.20) + (cl * 0.15) + (d * 0.15)

    score = round(max(0.0, min(10.0, score)), 1)

    # Score interpretation bands (Section 8)
    if score >= 9.8:
        label = "Exceptional"
    elif score >= 9.0:
        label = "Excellent"
    elif score >= 8.0:
        label = "Very Good"
    elif score >= 6.5:
        label = "Good"
    elif score >= 5.0:
        label = "Average"
    elif score >= 3.0:
        label = "Needs Significant Improvement"
    else:
        label = "Very Poor"

    return score, label

def clean_json_text(text):
    """Strip markdown code fences or surrounding text to extract valid JSON."""
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    # Find matching outermost braces
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start:end+1]
    return text

def repair_json(raw_text, key, model):
    """Controlled single repair attempt for malformed JSON using Gemini."""
    prompt = f"The following JSON is malformed. Fix syntax errors and return ONLY the valid corrected JSON object with no explanations or code fences:\n\n{raw_text[:2000]}"
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0.0, "responseMimeType": "application/json"}
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read().decode())
        repaired_text = data["candidates"][0]["content"]["parts"][0]["text"]
        return json.loads(clean_json_text(repaired_text))

def call_gemini_evaluation(input_data):
    """Call Google AI Studio Gemini API with input contract and validate result."""
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY is not configured on the Rehearse backend.")

    # Formulate prompt with input contract
    input_str = json.dumps(input_data, indent=2)
    context = (input_data.get("interview_context") or "").lower()
    company_guidelines = ""
    if "amazon" in context:
        company_guidelines = (
            "\nCOMPANY RUBRIC DIRECTIVE — AMAZON:\n"
            "- Explicitly evaluate against Amazon's Leadership Principles (Customer Obsession, Ownership, Bias for Action, Dive Deep, Deliver Results).\n"
            "- In feedback.what_went_well and feedback.what_to_improve, cite which Leadership Principles the candidate demonstrated or failed to embody.\n"
        )
    elif "google" in context or "alphabet" in context:
        company_guidelines = (
            "\nCOMPANY RUBRIC DIRECTIVE — GOOGLE:\n"
            "- Explicitly evaluate for General Cognitive Ability (GCA), Googleyness (navigating ambiguity, intellectual humility, doing the right thing), and scalable system thinking.\n"
        )
    elif "meta" in context or "facebook" in context:
        company_guidelines = (
            "\nCOMPANY RUBRIC DIRECTIVE — META:\n"
            "- Explicitly evaluate against Meta core values: Move Fast, Focus on Long-Term Impact, Build Awesome Things, and Live in the Future.\n"
        )
    elif "apple" in context:
        company_guidelines = (
            "\nCOMPANY RUBRIC DIRECTIVE — APPLE:\n"
            "- Explicitly evaluate for deep attention to detail, user privacy, product intuition, software craftsmanship, and cross-functional empathy.\n"
        )

    user_prompt = (
        f"Evaluate the candidate's answer with senior-level technical discernment and strong reasoning.\n"
        f"Analyze core principles, concrete mechanisms, edge cases, and architectural trade-offs.\n"
        f"{company_guidelines}\n"
        f"Input Context:\n{input_str}\n\n"
        f"Respond with strict pure JSON matching schema_version 1.0."
    )

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
    payload = {
        "contents": [
            {"role": "user", "parts": [{"text": MASTER_SYSTEM_PROMPT + "\n\n" + user_prompt}]}
        ],
        "generationConfig": {
            "temperature": 0.2,
            "responseMimeType": "application/json"
        }
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "RehearseBackend/1.0"}
    )

    start_time = time.time()
    max_retries = 3
    last_err = None

    for attempt in range(1, max_retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                elapsed = time.time() - start_time
                response_data = json.loads(resp.read().decode())
                candidate = response_data.get("candidates", [{}])[0]
                raw_output = candidate.get("content", {}).get("parts", [{}])[0].get("text", "")

                # Attempt JSON parse
                try:
                    parsed = json.loads(clean_json_text(raw_output))
                except Exception as parse_err:
                    print(f"[REPAIR] JSON parse failed: {parse_err}. Initiating single repair attempt...")
                    try:
                        parsed = repair_json(raw_output, GEMINI_API_KEY, GEMINI_MODEL)
                    except Exception as repair_err:
                        print(f"[REPAIR] Repair also failed: {repair_err}")
                        raise ValueError(f"Malformed JSON from AI model and repair failed: {parse_err}")

                # Programmatically calculate overall_score & label using Section 7 formulas
                q_type = input_data.get("question_type", parsed.get("question_type", "technical"))
                eval_dict = parsed.get("evaluation", {})
                add_rubric = parsed.get("additional_rubric", {})
                calculated_score, score_label = calculate_overall_score(q_type, eval_dict, add_rubric)

                parsed["overall_score"] = calculated_score
                parsed["score_label"] = score_label
                parsed["schema_version"] = SCHEMA_VERSION
                parsed["question_id"] = input_data.get("question_id", parsed.get("question_id", "q-1"))

                # Integrate audio/speech measurements if provided in transcript_analytics
                analytics = input_data.get("transcript_analytics", {})
                if "communication" in parsed and isinstance(parsed["communication"], dict):
                    parsed["communication"]["words_per_minute"] = analytics.get("words_per_minute")
                    parsed["communication"]["filler_word_count"] = analytics.get("filler_word_count")
                    parsed["communication"]["repeated_word_count"] = analytics.get("repeated_word_count")

                # Package unified envelope
                now_iso = datetime.now(timezone.utc).isoformat()
                return {
                    "provider": "google_gemini",
                    "model_id": GEMINI_MODEL,
                    "execution_mode": "online",
                    "evaluation_timestamp": now_iso,
                    "overall_score": calculated_score,
                    "evaluation_schema_version": SCHEMA_VERSION,
                    "latency_ms": int(elapsed * 1000),
                    "evaluation_result": parsed
                }

        except urllib.error.HTTPError as e:
            err_msg = e.read().decode()
            print(f"[WARN] Gemini API HTTP {e.code} (attempt {attempt}/{max_retries}): {err_msg[:200]}")
            last_err = RuntimeError(f"Gemini API error (HTTP {e.code}): {err_msg}")
            # Only retry transient errors (429 rate limit, 503 high demand, 500 server error)
            if e.code in [429, 500, 502, 503, 504] and attempt < max_retries:
                backoff = attempt * 2.0
                print(f"[RETRY] Backing off for {backoff:.1f}s before retry...")
                time.sleep(backoff)
                continue
            else:
                raise last_err
        except Exception as e:
            print(f"[WARN] Request error (attempt {attempt}/{max_retries}): {e}")
            last_err = e
            if attempt < max_retries:
                time.sleep(attempt * 1.5)
                continue
            else:
                raise last_err

    if last_err:
        raise last_err

def generate_fallback_tailored_questions(company: str, role: str, level: str, interview_type: str, count: int) -> dict:
    comp_name = company if company else "leading tech organization"
    is_tech = interview_type.lower() == "technical"
    role_lower = role.lower()

    if is_tech:
        if any(w in role_lower for w in ["ios", "apple", "swift", "mobile", "android"]):
            pool = [
                f"When developing software at {comp_name}, maintaining 60/120fps UI fluidity and minimal battery impact is critical. How do you architect view lifecycles, background synchronization, and state isolation to prevent main thread blocking in {role}?",
                f"Describe your approach to managing structured concurrency, data-race safety, and actor reentrancy when handling real-time data or audio streams in {role}.",
                f"Walk me through how you architect an offline-first caching and conflict resolution engine for a mobile app at {comp_name}, specifically handling degraded network connectivity.",
                f"How do you diagnose and eliminate persistent memory leaks, retain cycles, and retain count spikes using platform profiling tools?",
                f"Describe a situation where you had to refactor a core legacy module into modern modular packages while keeping build times minimal and zero regressions."
            ]
        elif any(w in role_lower for w in ["ml", "ai", "machine learning", "data"]):
            pool = [
                f"At {comp_name}, low-latency inference and real-time model serving are essential for {role}. How do you design an inference pipeline to meet sub-50ms p99 SLAs under high query volume?",
                f"How do you detect and mitigate feature drift, covariate shift, and label degradation in continuous production pipelines?",
                f"Explain how you design an evaluation harness and guardrails to benchmark LLM outputs and structured schema adherence in production.",
                f"Walk me through how you approach feature engineering and storage tradeoffs between a real-time feature store and offline batch data lakes.",
                f"Describe an instance where a model performed exceptionally well in offline validation but degraded in live A/B testing. How did you diagnose the root cause?"
            ]
        elif any(w in role_lower for w in ["backend", "distributed", "systems", "cloud", "platform", "sre", "devops"]):
            pool = [
                f"For a mission-critical backend service at {comp_name}, how do you ensure high availability and partition tolerance while preventing split-brain scenarios and data loss in {role}?",
                f"Walk me through how you implement distributed idempotency and distributed rate limiting across multi-region server clusters.",
                f"How do you design a database sharding and indexing strategy when a relational database exceeds write throughput limits?",
                f"Explain how you handle cascading failures, thundering herds, and circuit breaking when third-party upstream dependencies fail.",
                f"Describe your strategy for zero-downtime database schema migrations on tables containing hundreds of millions of active records."
            ]
        else:
            pool = [
                f"As a {level} {role} at {comp_name}, how do you structure an end-to-end architecture to balance fast iteration velocity with long-term maintainability and system resilience?",
                f"Describe how you design APIs and contracts between client consumers and distributed backend microservices to ensure graceful error handling and forward compatibility.",
                f"Walk me through a complex architectural tradeoff you made where you had to sacrifice one system property (e.g. strict consistency or simplicity) for another (e.g. low latency or availability).",
                f"How do you approach automated testing, end-to-end integration verification, and deployment safety in a continuous delivery pipeline?",
                f"If a sudden production incident spikes error rates by 15% immediately following a release, what is your systematic triage, isolation, and rollback process?"
            ]
    else:
        pool = [
            f"Tell me about a high-stakes technical initiative you drove as a {level} {role} at {comp_name} where you encountered conflicting cross-functional priorities. How did you achieve consensus?",
            f"Describe an instance where you pushed back against an unrealistic project deadline or scope requirement. What empirical data and architectural alternatives did you present to leadership?",
            f"Can you share an experience where a production bug or outage occurred due to an unforeseen edge case under your watch? How did you manage the immediate remediation and post-mortem?",
            f"How do you handle a situation where two senior engineers on your team strongly disagree on an architectural decision or technology choice?",
            f"Give an example of how you mentor other engineers and champion engineering excellence, code review rigor, and architectural standards within your team."
        ]

    selected = pool[:min(count, len(pool))]
    return {
        "questions": [
            {
                "id": f"q{i+1}",
                "question": q,
                "topic": f"{role} Competency",
                "origin": f"Tailored for {level} {role} at {comp_name}",
                "focus": "technical_depth" if is_tech else "leadership_and_collaboration"
            }
            for i, q in enumerate(selected)
        ]
    }

def call_gemini_generate_questions(input_data: dict) -> dict:
    company = input_data.get("company", "").strip() or "top-tier technology company"
    role = input_data.get("role", "").strip() or "Software Engineer"
    level = input_data.get("experience_level", "").strip() or "Intermediate"
    interview_type = input_data.get("interview_type", "technical").lower()
    duration_minutes = input_data.get("duration_minutes", 20)

    if duration_minutes <= 15:
        target_count = 3
    elif duration_minutes <= 25:
        target_count = 4
    else:
        target_count = 5

    skills = input_data.get("skills", [])
    skills_text = f"Key candidate skills: {', '.join(skills)}." if skills else ""
    resume_context = input_data.get("resume_context", "").strip()
    resume_text = f"Candidate background & projects:\n{resume_context}" if resume_context else ""

    if not GEMINI_API_KEY:
        print("[WARN] No GEMINI_API_KEY configured for question generation. Using role-tailored generator.")
        return generate_fallback_tailored_questions(company, role, level, interview_type, target_count)

    prompt = f"""You are a Principal Technical Interviewer and Hiring Bar Raiser at {company}.
You are conducting a high-signal, professional {interview_type.upper()} interview for a candidate applying for: {role} (Experience Level: {level}).

{skills_text}
{resume_text}

MANDATORY RULES:
1. ABSOLUTELY NO GENERIC OR TEXTBOOK QUESTIONS:
   - NEVER ask generic questions like "How would you design a distributed cache with LRU eviction", "Reverse a linked list", "What is an abstract class", or generic clichés.
   - Every single question must be deeply contextualized to {role} at {company}.
   - Tailor the terminology, domain challenges, constraints, and architecture to what an engineer in {role} at {company} actually encounters.
2. CALIBRATE TO EXPERIENCE LEVEL ({level}):
   - Junior/Intern: Concrete mechanisms, core language idioms, practical debugging intuition, and system fundamentals.
   - Mid-level: Real-world engineering tradeoffs, service interaction, error recovery, performance bottlenecks, and testing strategies.
   - Senior/Lead: High-scale architecture, concurrency, consistency vs availability tradeoffs, resilience under network/hardware faults, and cross-functional technical leadership.
3. LOGICAL PROGRESSION:
   - Generate exactly {target_count} questions.
   - Question 1 (The Opening Question): A high-impact, realistic problem setup directly targeting the core domain of {role} at {company}.
   - Middle Questions: Deep architectural tradeoffs, debugging subtle edge cases, or handling catastrophic failure scenarios.
   - Final Question: Pragmatic engineering leadership, metrics-driven decisions, or long-term maintainability tradeoffs.

RETURN ONLY VALID JSON MATCHING THIS EXACT SCHEMA:
{{
  "questions": [
    {{
      "id": "q1",
      "question": "Full verbatim question string that the interviewer will speak.",
      "topic": "Concise topic title",
      "origin": "Why this question was chosen for {role} at {company}",
      "focus": "Primary evaluation dimension"
    }}
  ]
}}"""

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}"
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "response_mime_type": "application/json",
            "temperature": 0.75,
            "max_output_tokens": 2048
        }
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "RehearseBackend/1.0"}
    )

    max_retries = 3
    for attempt in range(1, max_retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                response_data = json.loads(resp.read().decode())
                candidate = response_data.get("candidates", [{}])[0]
                raw_output = candidate.get("content", {}).get("parts", [{}])[0].get("text", "")
                parsed = json.loads(clean_json_text(raw_output))
                if "questions" in parsed and isinstance(parsed["questions"], list) and len(parsed["questions"]) > 0:
                    return parsed
                else:
                    raise ValueError("JSON response lacked valid 'questions' array")
        except Exception as e:
            print(f"[WARN] Question generation attempt {attempt}/{max_retries} failed: {e}")
            time.sleep(attempt * 1.5)

    print("[FALLBACK] Using intelligent role-tailored questions fallback.")
    return generate_fallback_tailored_questions(company, role, level, interview_type, target_count)

class RehearseAPIHandler(BaseHTTPRequestHandler):
    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        if self.path == "/health" or self.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self._send_cors_headers()
            self.end_headers()
            resp = {
                "status": "healthy",
                "service": "Rehearse AI Backend",
                "provider": "google_gemini",
                "model": GEMINI_MODEL,
                "key_configured": bool(GEMINI_API_KEY),
                "schema_version": SCHEMA_VERSION
            }
            self.wfile.write(json.dumps(resp).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/api/evaluate":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            try:
                input_data = json.loads(body)
                print(f"[API] Evaluating question: \"{input_data.get('question', '')[:60]}...\" (Candidate: {input_data.get('candidate_level', 'intermediate')})")
                
                result = call_gemini_evaluation(input_data)
                
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self._send_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps(result).encode("utf-8"))
            except ValueError as ve:
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self._send_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(ve)}).encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self._send_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))
        elif self.path == "/api/generate_questions":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            try:
                input_data = json.loads(body)
                company = input_data.get("company") or "Tech Company"
                role = input_data.get("role") or "Software Engineer"
                level = input_data.get("experience_level") or "Intermediate"
                print(f"[API] Generating tailored interview questions for {level} {role} at {company}...")

                result = call_gemini_generate_questions(input_data)

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self._send_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps(result).encode("utf-8"))
            except Exception as e:
                print(f"[ERROR] Generate questions failed: {e}")
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self._send_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

def run_server():
    server_address = ("0.0.0.0", PORT)
    httpd = HTTPServer(server_address, RehearseAPIHandler)
    print("=" * 70)
    print("  🚀 REHEARSE AI BACKEND SERVER RUNNING")
    print(f"  • Listening on: http://localhost:{PORT}")
    print(f"  • Provider:     Google Gemini")
    print(f"  • Model:        {GEMINI_MODEL}")
    print(f"  • Key present:  {bool(GEMINI_API_KEY)}")
    print("=" * 70)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server.")
        httpd.server_close()

if __name__ == "__main__":
    run_server()
