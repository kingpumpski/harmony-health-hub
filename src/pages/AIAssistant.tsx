import { useState, useRef, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { 
  Bot, Send, Sparkles, User, Loader2, Stethoscope, FlaskConical, 
  Pill, CreditCard, Utensils, Baby, HeartPulse, ClipboardList,
  Lightbulb, AlertTriangle, CheckCircle, Copy, ThumbsUp, ThumbsDown
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { toast } from '@/hooks/use-toast';

interface Message {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: Date;
}

interface AssistantConfig {
  id: string;
  name: string;
  description: string;
  icon: React.ElementType;
  color: string;
  systemPrompt: string;
  suggestedPrompts: string[];
}

const assistantConfigs: Record<string, AssistantConfig> = {
  nurse: {
    id: 'nurse',
    name: 'AI Nursing Assistant',
    description: 'Clinical support for nursing care, medication administration, and patient monitoring.',
    icon: HeartPulse,
    color: 'bg-pink-500',
    systemPrompt: `You are an AI nursing assistant for a healthcare facility. Help nurses with:
- Medication administration guidance and drug interaction checks
- Vital signs interpretation and trending analysis
- Patient assessment documentation
- Care plan recommendations
- Nursing interventions and best practices
- Wound care protocols
- Patient education materials
- Shift handoff summaries

Always remind nurses that AI suggestions should be verified with clinical judgment and facility protocols. For emergencies, always recommend immediate clinical intervention.`,
    suggestedPrompts: [
      'What are the normal ranges for vital signs in adults?',
      'Help me document a patient assessment',
      'What nursing interventions are recommended for post-operative care?',
      'Check for drug interactions between these medications',
    ],
  },
  lab_technician: {
    id: 'lab_technician',
    name: 'AI Lab Assistant',
    description: 'Laboratory analysis support, result interpretation, and quality control guidance.',
    icon: FlaskConical,
    color: 'bg-purple-500',
    systemPrompt: `You are an AI laboratory assistant. Help lab technicians with:
- Test result interpretation and reference ranges
- Quality control procedures
- Sample handling and storage guidelines
- Troubleshooting abnormal results
- Critical value identification and escalation
- Lab equipment maintenance schedules
- Test methodology explanations
- Documentation and reporting standards

Always emphasize that abnormal or critical results should be verified and reported through proper channels. Clinical correlation is essential.`,
    suggestedPrompts: [
      'What are the critical values for common lab tests?',
      'Help interpret this CBC result',
      'What could cause a falsely elevated glucose reading?',
      'Quality control procedures for hematology analyzer',
    ],
  },
  pharmacist: {
    id: 'pharmacist',
    name: 'AI Pharmacy Assistant',
    description: 'Medication management, drug interactions, dosing calculations, and inventory support.',
    icon: Pill,
    color: 'bg-green-500',
    systemPrompt: `You are an AI pharmacy assistant. Help pharmacists with:
- Drug interaction screening and severity assessment
- Dosing calculations and adjustments for special populations
- Therapeutic substitutions and alternatives
- Medication counseling points for patients
- Inventory management and reorder recommendations
- Compounding guidelines
- Prescription verification checks
- Adverse drug reaction monitoring

Always remind pharmacists to verify calculations independently and consult references for critical decisions. Patient safety is paramount.`,
    suggestedPrompts: [
      'Check drug interactions between these medications',
      'Calculate pediatric dosing for amoxicillin',
      'What are therapeutic alternatives for this medication?',
      'Counseling points for a new diabetic patient',
    ],
  },
  accountant: {
    id: 'accountant',
    name: 'AI Billing Assistant',
    description: 'Billing codes, insurance claims, financial reporting, and revenue cycle support.',
    icon: CreditCard,
    color: 'bg-blue-500',
    systemPrompt: `You are an AI billing and accounts assistant for a healthcare facility. Help with:
- Medical billing codes (ICD-10, CPT) selection and validation
- Insurance claim processing and denial management
- Payment reconciliation and aging reports
- Financial reporting and analytics
- Revenue cycle optimization
- Patient billing inquiries
- Insurance verification procedures
- Compliance with billing regulations

Always remind users to verify codes with official references and follow facility-specific billing policies.`,
    suggestedPrompts: [
      'What ICD-10 code should I use for hypertension?',
      'How to handle an insurance claim denial?',
      'Generate a summary of outstanding payments',
      'Best practices for reducing claim rejections',
    ],
  },
  canteen: {
    id: 'canteen',
    name: 'AI Dietary Assistant',
    description: 'Meal planning, nutritional requirements, dietary restrictions, and kitchen operations.',
    icon: Utensils,
    color: 'bg-orange-500',
    systemPrompt: `You are an AI dietary and canteen assistant for a healthcare facility. Help with:
- Therapeutic diet planning for various conditions
- Nutritional calculations and meal balancing
- Allergen management and cross-contamination prevention
- Special dietary requirements (diabetic, renal, cardiac diets)
- Menu planning and seasonal adjustments
- Food safety and HACCP compliance
- Patient meal preferences and modifications
- Kitchen inventory and ordering

Always emphasize food safety protocols and proper documentation of patient dietary restrictions.`,
    suggestedPrompts: [
      'Plan a diabetic-friendly menu for the week',
      'What foods should be avoided for renal patients?',
      'Calculate nutritional values for this meal',
      'Food safety guidelines for meal preparation',
    ],
  },
  midwife: {
    id: 'midwife',
    name: 'AI Maternity Assistant',
    description: 'Prenatal care guidance, labor monitoring, and maternal health support.',
    icon: Baby,
    color: 'bg-pink-400',
    systemPrompt: `You are an AI maternity and midwifery assistant. Help midwives with:
- Prenatal assessment and monitoring guidelines
- Labor progress evaluation and documentation
- Newborn assessment protocols
- Breastfeeding support and education
- Postpartum care recommendations
- High-risk pregnancy indicators
- Emergency obstetric protocols
- Patient education for expectant mothers

Always emphasize that clinical judgment is essential and any emergency situations require immediate clinical intervention. Patient safety is paramount.`,
    suggestedPrompts: [
      'Normal labor progress milestones',
      'Warning signs during pregnancy to watch for',
      'Breastfeeding positioning and latch guidance',
      'Postpartum recovery timeline and care',
    ],
  },
  front_desk: {
    id: 'front_desk',
    name: 'AI Reception Assistant',
    description: 'Patient scheduling, registration support, and front office operations.',
    icon: ClipboardList,
    color: 'bg-teal-500',
    systemPrompt: `You are an AI front desk and reception assistant. Help with:
- Patient registration procedures and documentation
- Appointment scheduling and optimization
- Insurance verification processes
- Patient communication templates
- Wait time management strategies
- Check-in and check-out procedures
- Handling patient inquiries and complaints
- Coordination with clinical departments

Always maintain patient confidentiality and follow facility protocols for information sharing.`,
    suggestedPrompts: [
      'How to handle an upset patient professionally',
      'Best practices for appointment scheduling',
      'What documents are needed for new patient registration?',
      'Template for appointment reminder messages',
    ],
  },
  practitioner: {
    id: 'practitioner',
    name: 'AI Clinical Decision Support',
    description: 'Diagnostic assistance, treatment guidelines, and evidence-based recommendations.',
    icon: Stethoscope,
    color: 'bg-primary',
    systemPrompt: `You are an AI clinical decision support system for healthcare practitioners. Help with:
- Differential diagnosis suggestions based on symptoms
- Evidence-based treatment guidelines
- Drug prescribing recommendations and dosing
- Clinical pathway guidance
- Medical literature summaries
- Documentation assistance for clinical notes
- Referral recommendations
- Patient education materials

IMPORTANT: All suggestions are for informational purposes only. Clinical decisions must be made by qualified healthcare providers based on individual patient assessment. Always verify information with current clinical guidelines.`,
    suggestedPrompts: [
      'Differential diagnosis for chest pain',
      'First-line treatment for uncomplicated UTI',
      'When to refer for specialist consultation',
      'Evidence-based management of hypertension',
    ],
  },
};

export default function AIAssistant() {
  const { user } = useAuth();
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  
  // Get the appropriate assistant config based on user role
  const role = user?.role || 'patient';
  const config = assistantConfigs[role] || assistantConfigs.practitioner;
  const AssistantIcon = config.icon;

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  const handleSend = async () => {
    if (!input.trim() || isLoading) return;

    const userMessage: Message = {
      id: Date.now().toString(),
      role: 'user',
      content: input.trim(),
      timestamp: new Date(),
    };

    setMessages(prev => [...prev, userMessage]);
    setInput('');
    setIsLoading(true);

    try {
      const { data, error } = await supabase.functions.invoke('ai-clinical-assist', {
        body: {
          mode: 'chat',
          role: role,
          message: userMessage.content,
          systemPrompt: config.systemPrompt,
          history: messages.slice(-10).map(m => ({
            role: m.role,
            content: m.content,
          })),
        },
      });

      if (error) throw error;

      const assistantMessage: Message = {
        id: (Date.now() + 1).toString(),
        role: 'assistant',
        content: data?.content || 'I apologize, but I was unable to generate a response. Please try again.',
        timestamp: new Date(),
      };

      setMessages(prev => [...prev, assistantMessage]);
    } catch (err: any) {
      console.error('AI chat error:', err);
      toast({
        title: 'Error',
        description: err.message || 'Failed to get AI response',
        variant: 'destructive',
      });
      
      // Add error message
      setMessages(prev => [...prev, {
        id: (Date.now() + 1).toString(),
        role: 'assistant',
        content: 'I apologize, but I encountered an error. Please try again or contact support if the issue persists.',
        timestamp: new Date(),
      }]);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSuggestedPrompt = (prompt: string) => {
    setInput(prompt);
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    toast({ title: 'Copied to clipboard' });
  };

  return (
    <div className="h-[calc(100vh-8rem)] flex flex-col animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-4">
          <div className={cn('w-12 h-12 rounded-xl flex items-center justify-center text-white', config.color)}>
            <AssistantIcon className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
              {config.name}
              <Sparkles className="w-5 h-5 text-primary" />
            </h1>
            <p className="text-muted-foreground text-sm">{config.description}</p>
          </div>
        </div>
      </div>

      {/* Chat Area */}
      <div className="flex-1 card-medical overflow-hidden flex flex-col">
        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center p-6">
              <div className={cn('w-20 h-20 rounded-2xl flex items-center justify-center text-white mb-4', config.color)}>
                <Bot className="w-10 h-10" />
              </div>
              <h2 className="text-xl font-semibold mb-2">Welcome to {config.name}</h2>
              <p className="text-muted-foreground mb-6 max-w-md">
                I&apos;m here to assist you with your daily tasks. Ask me anything related to your role, 
                or try one of the suggested prompts below.
              </p>
              
              {/* Suggested Prompts */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3 w-full max-w-2xl">
                {config.suggestedPrompts.map((prompt, idx) => (
                  <button
                    key={idx}
                    onClick={() => handleSuggestedPrompt(prompt)}
                    className="flex items-start gap-3 p-4 rounded-xl border border-border hover:border-primary hover:bg-primary/5 transition-all text-left"
                  >
                    <Lightbulb className="w-5 h-5 text-primary flex-shrink-0 mt-0.5" />
                    <span className="text-sm">{prompt}</span>
                  </button>
                ))}
              </div>

              {/* Disclaimer */}
              <div className="mt-6 p-4 rounded-xl bg-warning/10 border border-warning/30 max-w-2xl">
                <div className="flex items-start gap-3">
                  <AlertTriangle className="w-5 h-5 text-warning flex-shrink-0" />
                  <p className="text-sm text-muted-foreground">
                    <span className="font-medium text-foreground">Disclaimer:</span> AI suggestions are for informational purposes only. 
                    Always verify information and use professional judgment in clinical decisions.
                  </p>
                </div>
              </div>
            </div>
          ) : (
            <>
              {messages.map((message) => (
                <div
                  key={message.id}
                  className={cn(
                    'flex gap-3',
                    message.role === 'user' ? 'justify-end' : 'justify-start'
                  )}
                >
                  {message.role === 'assistant' && (
                    <div className={cn('w-8 h-8 rounded-lg flex items-center justify-center text-white flex-shrink-0', config.color)}>
                      <Bot className="w-4 h-4" />
                    </div>
                  )}
                  
                  <div
                    className={cn(
                      'max-w-[80%] rounded-2xl p-4',
                      message.role === 'user'
                        ? 'bg-primary text-primary-foreground'
                        : 'bg-muted'
                    )}
                  >
                    <div className="whitespace-pre-wrap text-sm">{message.content}</div>
                    
                    {message.role === 'assistant' && (
                      <div className="flex items-center gap-2 mt-3 pt-3 border-t border-border/50">
                        <button
                          onClick={() => copyToClipboard(message.content)}
                          className="p-1.5 rounded-lg hover:bg-background/50 transition-colors"
                          title="Copy to clipboard"
                        >
                          <Copy className="w-4 h-4 text-muted-foreground" />
                        </button>
                        <button
                          className="p-1.5 rounded-lg hover:bg-background/50 transition-colors"
                          title="Helpful"
                        >
                          <ThumbsUp className="w-4 h-4 text-muted-foreground" />
                        </button>
                        <button
                          className="p-1.5 rounded-lg hover:bg-background/50 transition-colors"
                          title="Not helpful"
                        >
                          <ThumbsDown className="w-4 h-4 text-muted-foreground" />
                        </button>
                        <span className="text-xs text-muted-foreground ml-auto">
                          {message.timestamp.toLocaleTimeString()}
                        </span>
                      </div>
                    )}
                  </div>

                  {message.role === 'user' && (
                    <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center flex-shrink-0">
                      <User className="w-4 h-4" />
                    </div>
                  )}
                </div>
              ))}
              
              {isLoading && (
                <div className="flex gap-3 justify-start">
                  <div className={cn('w-8 h-8 rounded-lg flex items-center justify-center text-white flex-shrink-0', config.color)}>
                    <Bot className="w-4 h-4" />
                  </div>
                  <div className="bg-muted rounded-2xl p-4">
                    <div className="flex items-center gap-2">
                      <Loader2 className="w-4 h-4 animate-spin" />
                      <span className="text-sm text-muted-foreground">Thinking...</span>
                    </div>
                  </div>
                </div>
              )}
              
              <div ref={messagesEndRef} />
            </>
          )}
        </div>

        {/* Input Area */}
        <div className="p-4 border-t border-border">
          <div className="flex gap-3">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && handleSend()}
              placeholder="Type your message..."
              className="flex-1 input-medical"
              disabled={isLoading}
            />
            <button
              onClick={handleSend}
              disabled={!input.trim() || isLoading}
              className="btn-primary px-4"
            >
              {isLoading ? (
                <Loader2 className="w-5 h-5 animate-spin" />
              ) : (
                <Send className="w-5 h-5" />
              )}
            </button>
          </div>
          <p className="text-xs text-muted-foreground text-center mt-2">
            AI responses are generated for informational purposes. Always verify with clinical guidelines.
          </p>
        </div>
      </div>
    </div>
  );
}
