import { GoogleGenerativeAI } from "@google/generative-ai";
import { NextResponse } from "next/server";

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || "");

export async function POST(req: Request) {
  try {
    const { mood } = await req.json();

    const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

    const prompt = `You are a calming breathing guide. The user is feeling "${mood}".
    Provide a set of 4 very short, calming instructions (max 3 words each) for a box breathing cycle (Inhale, Hold, Exhale, Hold).
    Format the response as a JSON object with keys: "in", "hold_in", "out", "hold_out".
    Also provide a short "completed" message (max 5 words).`;

    const result = await model.generateContent(prompt);
    const responseText = result.response.text();

    // Extract JSON from response (sometimes Gemini adds markdown formatting)
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    const instructions = jsonMatch ? JSON.parse(jsonMatch[0]) : {
      in: "Breathe in",
      hold_in: "Hold",
      out: "Breathe out",
      hold_out: "Hold",
      completed: "Be easy, breathe deeply"
    };

    return NextResponse.json(instructions);
  } catch (error) {
    console.error("Gemini API Error:", error);
    return NextResponse.json({
      in: "Breathe in",
      hold_in: "Hold",
      out: "Breathe out",
      hold_out: "Hold",
      completed: "Be easy, breathe deeply"
    }, { status: 200 }); // Fallback to defaults
  }
}
