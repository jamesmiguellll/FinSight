from fastapi import FastAPI, HTTPException, Depends, Header, Request
from pydantic import BaseModel
from google import genai
from google.genai import types as genai_types
import os
from dotenv import load_dotenv
import pandas as pd
from sklearn.linear_model import LinearRegression
import numpy as np
from supabase import create_client, Client
import json
import logging
# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="FinSight AI Microservice")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins for local testing
    allow_credentials=False,
    allow_methods=["*"],  # Allows all methods
    allow_headers=["*"],  # Allows all headers
)

# --- Configuration ---
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY") # Use service role key to bypass RLS for aggregation, or handle RLS via user's JWT.

# Initialize Gemini Client using AI Studio
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
genai_client = None

if GEMINI_API_KEY:
    try:
        genai_client = genai.Client(api_key=GEMINI_API_KEY)
        logger.info("Gemini AI Studio client initialized successfully.")
    except Exception as e:
        logger.error(f"Failed to initialize Gemini client: {e}")
else:
    logger.error("GEMINI_API_KEY not set. AI features will be unavailable.")

# Initialize Supabase client
if SUPABASE_URL and SUPABASE_KEY:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
else:
    supabase = None
    logger.warning("Supabase URL or Key is missing. Connect to database will fail.")


# --- Models ---
class CategorizeRequest(BaseModel):
    merchant_name: str

class CategorizeResponse(BaseModel):
    category: str
    confidence: float

class GoalPlanRequest(BaseModel):
    user_id: str
    target_amount: float
    deadline_months: int

class InsightRequest(BaseModel):
    period: str
    total_income: float
    total_expense: float
    category_totals: dict
    recent_transactions: list

class InsightResponse(BaseModel):
    insight: str

class TransactionRequest(BaseModel):
    title: str
    amount: float
    category: str
    type: str
    created_at: str = None

# --- Endpoints ---

async def verify_jwt(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    token = authorization.split(" ")[1]
    
    if not supabase:
        # If Supabase is not configured, we might bypass or fail depending on strictness. 
        # For now, if no DB, let's just log a warning but let it pass for local testing
        logger.warning("Supabase not configured, skipping JWT verification")
        return token
        
    try:
        # Verify token by fetching user from Supabase
        user_resp = supabase.auth.get_user(token)
        if not user_resp or not user_resp.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user_resp.user
    except Exception as e:
        logger.error(f"JWT Verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid or expired token")

@app.get("/")
def read_root():
    return {"status": "FinSight AI Microservice is running."}

@app.post("/predict-category", response_model=CategorizeResponse)
async def predict_category(request: CategorizeRequest, user=Depends(verify_jwt)):
    """
    Accepts a merchant name and uses Gemini to predict the category.
    Tries standard categories first, then infers dynamic ones (e.g., Entertainment).
    """
    merchant = request.merchant_name.strip()
    if not merchant:
        raise HTTPException(status_code=400, detail="Merchant name is required")
        
    if not genai_client:
        # Fallback to simple rule-based if no model
        category = "Miscellaneous"
        return CategorizeResponse(category=category, confidence=0.5)

    prompt = f"""
    You are a personal finance categorization engine for the Philippines.
    Categorize this merchant or product name: "{merchant}".

    Common Filipino brands to recognize:
    - Food: Jollibee, McDonald's, KFC, Chowking, Mang Inasal, Greenwich, Yellow Cab, Starbucks, 7-Eleven, GrabFood, foodpanda, Max's, Red Ribbon, Goldilocks, SM Food Court
    - Transport: Angkas, Grab, JoyRide, Beep, MRT, LRT, Jeep, Bus, Taxi, Lalamove, J&T
    - Bills: Meralco, Maynilad, Manila Water, PLDT, Globe, Smart, Converge, Sky Cable, Netflix, Spotify, PhilHealth, SSS, Pag-IBIG
    - Shopping: Shopee, Lazada, Zalora, SM, Robinsons, Ayala Malls, H&M, Uniqlo, Nike, Adidas
    - Entertainment: Cinema, Netflix, Spotify, Steam, Games, Resorts World, Okada
    - Healthcare: Mercury Drug, Watsons, Rose Pharmacy, Hospital, Clinic, Doctor, Dental
    - Education: Tuition, Books, School, University

    Rules:
    - ALWAYS pick the most reasonable category — never return "Miscellaneous" or "Others".
    - If it is an edible item (like "cake", "bread", "burger", "rice", "coffee"), it MUST be categorized as "Food".
    - If a product name (like "shoes", "shirt", "groceries") is mentioned, infer from context.
    - Clothing/gadgets/household items = Shopping
    - When unsure, pick the closest match from: Food, Transport, Bills, Shopping, Entertainment, Healthcare, Education

    Reply with ONLY valid JSON: {{"category": "CategoryName", "confidence": 0.95}}
    """
    try:
        response = genai_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt,
            config=genai_types.GenerateContentConfig(
                response_mime_type="application/json"
            )
        )
        
        result = json.loads(response.text.strip())
        category = result.get("category", "Miscellaneous").title()
        confidence = float(result.get("confidence", 0.5))
        return CategorizeResponse(category=category, confidence=confidence)
    except Exception as e:
        logger.error(f"Error predicting category: {e}")
        
        # Safe Fallback if Vertex AI is offline or misconfigured
        category = "Miscellaneous"
        food_keywords = ['mcdonalds', 'kfc', 'restaurant', 'food', 'eats', 'jollibee', 'mang inasal', 'chowking', 'cake', 'bread', 'rice', 'meal', 'water', 'coffee', 'burger', 'drink', 'cookie', 'biscuit', 'snack', 'candy', 'chocolate', 'pizza', 'pasta']
        transport_keywords = ['angkas', 'joyride', 'grab', 'uber', 'ltfrb', 'mrt', 'lrt', 'beep', 'gas', 'fare', 'toll', 'parking', 'taxi', 'bus', 'jeep']
        bills_keywords = ['meralco', 'maynilad', 'pldt', 'globe', 'smart', 'converge', 'water', 'electricity', 'internet', 'rent', 'subscription']
        shopping_keywords = ['shopee', 'lazada', 'zalora', 'shein', 'mall', 'grocery', 'supermarket', 'sm ', 'robinsons', 'clothes', 'shorts', 'shirt', 'pants', 'shoes', 'dress', 'jacket', 'apparel', 'gadget']
        
        lower_merchant = merchant.lower()
        if any(word in lower_merchant for word in food_keywords):
            category = "Food"
        elif any(word in lower_merchant for word in transport_keywords):
            category = "Transport"
        elif any(word in lower_merchant for word in bills_keywords):
            category = "Bills"
        elif any(word in lower_merchant for word in shopping_keywords):
            category = "Shopping"
            
        return CategorizeResponse(category=category, confidence=0.0)



@app.post("/add-transaction")
async def add_transaction(request: TransactionRequest, user=Depends(verify_jwt)):
    if not supabase:
        raise HTTPException(status_code=500, detail="Database not configured")

    try:
        # Generate embedding (skip if API quota is exhausted — don't block the request)
        embedding = None
        if genai_client:
            text_to_embed = f"{request.title} - {request.category} - {request.type} - {request.amount}"
            try:
                emb_res = genai_client.models.embed_content(
                    model="text-embedding-004",
                    contents=text_to_embed
                )
                embedding = emb_res.embeddings[0].values
            except Exception as e:
                logger.warning(f"Skipping embedding (non-blocking): {e}")

        # Insert into DB
        data = {
            "user_id": user.id,
            "title": request.title,
            "amount": request.amount,
            "category": request.category,
            "type": request.type
        }
        if request.created_at:
            data["created_at"] = request.created_at
        if embedding:
            data["embedding"] = embedding

        result = supabase.table("transactions").insert(data).execute()
        
        return {"message": "Transaction added", "data": result.data}
    except Exception as e:
        logger.error(f"Error adding transaction: {e}")
        raise HTTPException(status_code=500, detail=str(e))

def _compute_goal_fallback(target_amount: float, deadline_months: int, total_income: float = 0.0, total_expense: float = 0.0) -> dict:
    """Compute a goal plan locally without calling Gemini."""
    monthly_savings_needed = target_amount / max(deadline_months, 1)
    weekly_savings_needed = monthly_savings_needed / 4.33
    monthly_surplus = total_income - total_expense

    if monthly_surplus > 0 and monthly_surplus >= monthly_savings_needed:
        tip = f"You have enough monthly surplus to reach this goal — set aside ₱{monthly_savings_needed:.0f} automatically each month."
    elif monthly_surplus > 0:
        tip = f"Reduce discretionary spending by ₱{(monthly_savings_needed - monthly_surplus):.0f}/month to stay on track with your goal."
    else:
        tip = f"Save ₱{weekly_savings_needed:.0f} per week by cutting non-essential expenses like dining out or subscriptions."

    return {
        "weekly_savings": round(weekly_savings_needed, 2),
        "tip": tip,
        "source": "calculated"
    }

@app.post("/suggest-goal-plan")
async def suggest_goal_plan(request: GoalPlanRequest, user=Depends(verify_jwt)):
    monthly_savings_needed = request.target_amount / max(request.deadline_months, 1)
    weekly_savings_needed = monthly_savings_needed / 4.33
    total_income = 0.0
    total_expense = 0.0

    # Fetch transaction totals if supabase is available
    if supabase:
        try:
            tx_resp = supabase.table('transactions') \
                .select('amount, type') \
                .eq('user_id', request.user_id) \
                .execute()
            transactions = tx_resp.data
            total_income = sum(t['amount'] for t in transactions if t['type'] == 'income')
            total_expense = sum(t['amount'] for t in transactions if t['type'] == 'expense')
        except Exception as db_err:
            logger.warning(f"Could not fetch transactions for goal plan: {db_err}")

    # If Gemini is unavailable, return computed fallback immediately
    if not genai_client:
        logger.warning("Gemini unavailable — returning computed goal plan fallback.")
        return _compute_goal_fallback(request.target_amount, request.deadline_months, total_income, total_expense)

    prompt = f"""
    You are a financial planning engine. The user wants to save ₱{request.target_amount:.2f} in {request.deadline_months} months.
    Their total logged income is ₱{total_income:.2f} and total logged expenses are ₱{total_expense:.2f}.
    To reach the goal, they need to save approximately ₱{monthly_savings_needed:.2f} per month or ₱{weekly_savings_needed:.2f} per week.

    Suggest a realistic weekly savings amount (as a number), and a very short 1-sentence actionable tip on how they can achieve this goal.
    Return strictly JSON in the format:
    {{"weekly_savings": {weekly_savings_needed:.2f}, "tip": "Cut down on food delivery to hit your goal."}}
    Do not add markdown formatting. Do not include any text outside the JSON.
    """

    import re
    text = ""
    try:
        response = genai_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt
        )
        text = response.text.strip()
        text = re.sub(r'```(?:json)?\s*', '', text)
        text = text.replace('```', '')
        match = re.search(r'\{.*?\}', text, re.DOTALL)
        if match:
            text = match.group(0)
        result = json.loads(text)
        result['weekly_savings'] = float(result.get('weekly_savings', weekly_savings_needed))
        return result
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error in goal plan: {e}, text was: {text}")
        return _compute_goal_fallback(request.target_amount, request.deadline_months, total_income, total_expense)
    except Exception as e:
        error_str = str(e)
        # Gracefully handle quota exhaustion and other API errors
        if any(keyword in error_str for keyword in ["429", "quota", "RESOURCE_EXHAUSTED", "rate limit", "403", "PERMISSION_DENIED"]):
            logger.warning(f"Gemini API limit hit — returning computed goal plan fallback. Reason: {error_str[:200]}")
            return _compute_goal_fallback(request.target_amount, request.deadline_months, total_income, total_expense)
        logger.error(f"Error suggesting goal plan: {e}")
        # Final safety net — always return something useful
        return _compute_goal_fallback(request.target_amount, request.deadline_months, total_income, total_expense)

@app.post("/generate-insight", response_model=InsightResponse)
async def generate_insight(request: InsightRequest, user=Depends(verify_jwt)):
    """
    Generates financial insights based on the user's spending data using Gemini on Vertex AI.
    """
    if not genai_client:
        raise HTTPException(status_code=500, detail="Gemini model not configured")

    data_summary = {
        "period": request.period,
        "totalIncome": request.total_income,
        "totalExpense": request.total_expense,
        "categoryTotals": request.category_totals,
        "recentTransactions": request.recent_transactions
    }

    prompt = f"""
    You are a brilliant personal finance advisor. Analyze the following budget and transaction data for the user:
    {json.dumps(data_summary)}

    Based on this data, provide EXACTLY ONE highly actionable, personalized financial insight, tips, or warning (max 100 characters/1 sentence).
    Make it encouraging, smart, and direct. Refer to specific categories or payees if interesting (e.g., "Your Food expenses are at 80% of limit - try cooking at home this week!").
    Do not include any greeting, intro, markdown bolding, or markdown surrounding your response. Just reply with the raw single-sentence advice.
    """

    try:
        response = genai_client.models.generate_content(
            model="gemini-2.0-flash",
            contents=prompt
        )
        return InsightResponse(insight=response.text.strip())
    except Exception as e:
        logger.error(f"Error generating insight: {e}")
        raise HTTPException(status_code=500, detail=str(e))

