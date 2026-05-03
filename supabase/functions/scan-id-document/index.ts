import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MODEL = 'google/gemini-2.5-flash';

interface ExtractedData {
  firstName?: string;
  lastName?: string;
  dateOfBirth?: string;
  gender?: string;
  ghanaCardNumber?: string;
  address?: string;
  city?: string;
  phone?: string;
  email?: string;
  documentType?: string;
  confidence?: number;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const formData = await req.formData();
    const file = formData.get('file') as File;
    
    if (!file) {
      return new Response(
        JSON.stringify({ error: 'No file provided' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const apiKey = Deno.env.get('LOVABLE_API_KEY');
    if (!apiKey) {
      throw new Error('LOVABLE_API_KEY not configured');
    }

    // Convert file to base64
    const arrayBuffer = await file.arrayBuffer();
    const base64 = btoa(String.fromCharCode(...new Uint8Array(arrayBuffer)));
    const mimeType = file.type || 'image/jpeg';

    const systemPrompt = `You are an AI assistant specialized in extracting personal information from ID documents (national IDs, passports, driver's licenses, Ghana cards, etc.).

Extract the following information from the provided ID document image:
- firstName: First name or given names
- lastName: Last name or surname
- dateOfBirth: Date of birth in YYYY-MM-DD format
- gender: male, female, or other
- ghanaCardNumber: National ID number (Ghana Card, passport number, or similar)
- address: Street address if visible
- city: City or town if visible
- phone: Phone number if visible
- documentType: Type of document (e.g., "Ghana Card", "Passport", "Driver's License")
- confidence: Your confidence level in the extraction (0-100)

Important rules:
1. Only extract information that is clearly visible in the document
2. Use null for any field that cannot be extracted
3. Format dates as YYYY-MM-DD
4. Return ONLY valid JSON, no additional text
5. If the image is not an ID document, return {"error": "Not a valid ID document", "confidence": 0}`;

    const userPrompt = `Extract personal information from this ID document image. Return ONLY valid JSON with the extracted fields.`;

    // Call AI API with vision capability
    const aiRes = await fetch('https://ai.gateway.lovable.dev/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [
          { role: 'system', content: systemPrompt },
          {
            role: 'user',
            content: [
              { type: 'text', text: userPrompt },
              {
                type: 'image_url',
                image_url: {
                  url: `data:${mimeType};base64,${base64}`,
                },
              },
            ],
          },
        ],
        max_tokens: 1000,
      }),
    });

    if (aiRes.status === 429) {
      return new Response(
        JSON.stringify({ error: 'AI rate limit reached, try again shortly.' }),
        { status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (aiRes.status === 402) {
      return new Response(
        JSON.stringify({ error: 'AI credits exhausted. Please contact administrator.' }),
        { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!aiRes.ok) {
      console.error('AI API error:', await aiRes.text());
      return new Response(
        JSON.stringify({ error: 'AI processing failed' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const data = await aiRes.json();
    const content = data.choices?.[0]?.message?.content ?? '';

    // Parse the AI response as JSON
    let extracted: ExtractedData;
    try {
      // Clean up potential markdown formatting
      const jsonStr = content.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
      extracted = JSON.parse(jsonStr);
    } catch (parseError) {
      console.error('Failed to parse AI response:', content);
      return new Response(
        JSON.stringify({ 
          error: 'Failed to parse document data',
          raw: content 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        data: extracted,
        message: extracted.confidence && extracted.confidence >= 80 
          ? 'Document scanned successfully' 
          : 'Document scanned with low confidence - please verify the information'
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (e) {
    console.error('Error:', e);
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
