import React, { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { CreatePatientSchema, CreatePatient, Gender, MaritalStatus } from '@/schemas/medicalSchemas';
import { getIcon } from '@/constants/medicalIcons';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Checkbox } from '@/components/ui/checkbox';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { AlertCircle, Check } from 'lucide-react';

/**
 * Patient Registration Component
 * Handles new patient onboarding and data collection
 * Includes medical history, allergies, medications tracking
 */

export const PatientRegistration: React.FC = () => {
  const [step, setStep] = useState(1);
  const [submitSuccess, setSubmitSuccess] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors, isSubmitting },
    control,
    reset,
  } = useForm<CreatePatient>({
    resolver: zodResolver(CreatePatientSchema),
    mode: 'onChange',
  });

  const allergiesValue = watch('allergies') || [];
  const medicationsValue = watch('medications') || [];

  const onSubmit = async (data: CreatePatient) => {
    try {
      setSubmitError(null);
      // TODO: Send to backend API
      console.log('Patient Registration Data:', data);

      // Simulate API call
      await new Promise((resolve) => setTimeout(resolve, 1000));

      setSubmitSuccess(true);
      reset();

      // Reset success message after 3 seconds
      setTimeout(() => setSubmitSuccess(false), 3000);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Registration failed. Please try again.';
      setSubmitError(message);
    }
  };

  const renderStepIndicator = () => (
    <div className="mb-8 flex justify-between">
      {[1, 2, 3, 4].map((s) => (
        <div key={s} className="flex flex-col items-center">
          <div
            className={`mb-2 flex h-10 w-10 items-center justify-center rounded-full border-2 ${
              step >= s
                ? 'border-blue-600 bg-blue-600 text-white'
                : 'border-gray-300 bg-gray-100 text-gray-600'
            }`}
          >
            {step > s ? <Check className="h-6 w-6" /> : s}
          </div>
          <span className="text-xs font-semibold capitalize text-gray-700">
            {['Personal', 'Medical', 'Emergency', 'Review'][s - 1]}
          </span>
        </div>
      ))}
    </div>
  );

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 px-4 py-8">
      <div className="mx-auto max-w-2xl">
        {/* Header */}
        <div className="mb-8 text-center">
          <div className="mb-4 flex justify-center">
            <div className="rounded-lg bg-white p-3 shadow-lg">
              {React.createElement(getIcon('PATIENT', 'role'), {
                className: 'h-8 w-8 text-blue-600',
              })}
            </div>
          </div>
          <h1 className="mb-2 text-3xl font-bold text-gray-900">Patient Registration</h1>
          <p className="text-gray-600">Welcome to Harmony Health Hub - Fertility Clinic</p>
        </div>

        {/* Success Alert */}
        {submitSuccess && (
          <div className="mb-6 flex items-center gap-3 rounded-lg bg-green-50 p-4 text-green-800">
            <Check className="h-5 w-5" />
            <span>Patient registration completed successfully!</span>
          </div>
        )}

        {/* Error Alert */}
        {submitError && (
          <div className="mb-6 flex items-center gap-3 rounded-lg bg-red-50 p-4 text-red-800">
            <AlertCircle className="h-5 w-5" />
            <span>{submitError}</span>
          </div>
        )}

        <Card className="shadow-xl">
          <CardHeader>
            <CardTitle>Register New Patient</CardTitle>
            <CardDescription>Step {step} of 4</CardDescription>
          </CardHeader>

          <CardContent>
            {renderStepIndicator()}

            <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
              {/* Step 1: Personal Information */}
              {step === 1 && (
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-gray-900">Personal Information</h3>

                  <div className="grid gap-4 md:grid-cols-2">
                    <div>
                      <Label htmlFor="first_name">First Name *</Label>
                      <Input
                        id="first_name"
                        placeholder="John"
                        {...register('first_name')}
                        className={errors.first_name ? 'border-red-500' : ''}
                      />
                      {errors.first_name && (
                        <p className="mt-1 text-sm text-red-500">{errors.first_name.message}</p>
                      )}
                    </div>

                    <div>
                      <Label htmlFor="last_name">Last Name *</Label>
                      <Input
                        id="last_name"
                        placeholder="Doe"
                        {...register('last_name')}
                        className={errors.last_name ? 'border-red-500' : ''}
                      />
                      {errors.last_name && (
                        <p className="mt-1 text-sm text-red-500">{errors.last_name.message}</p>
                      )}
                    </div>
                  </div>

                  <div>
                    <Label htmlFor="email">Email Address</Label>
                    <Input
                      id="email"
                      type="email"
                      placeholder="john@example.com"
                      {...register('email')}
                      className={errors.email ? 'border-red-500' : ''}
                    />
                    {errors.email && (
                      <p className="mt-1 text-sm text-red-500">{errors.email.message}</p>
                    )}
                  </div>

                  <div>
                    <Label htmlFor="phone">Phone Number *</Label>
                    <Input
                      id="phone"
                      type="tel"
                      placeholder="+1 (555) 123-4567"
                      {...register('phone')}
                      className={errors.phone ? 'border-red-500' : ''}
                    />
                    {errors.phone && (
                      <p className="mt-1 text-sm text-red-500">{errors.phone.message}</p>
                    )}
                  </div>

                  <div className="grid gap-4 md:grid-cols-2">
                    <div>
                      <Label htmlFor="date_of_birth">Date of Birth *</Label>
                      <Input
                        id="date_of_birth"
                        type="date"
                        {...register('date_of_birth', {
                          valueAsDate: true,
                        })}
                        className={errors.date_of_birth ? 'border-red-500' : ''}
                      />
                      {errors.date_of_birth && (
                        <p className="mt-1 text-sm text-red-500">{errors.date_of_birth.message}</p>
                      )}
                    </div>

                    <div>
                      <Label htmlFor="gender">Gender *</Label>
                      <Select>
                        <SelectTrigger id="gender" className={errors.gender ? 'border-red-500' : ''}>
                          <SelectValue placeholder="Select gender" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="MALE">Male</SelectItem>
                          <SelectItem value="FEMALE">Female</SelectItem>
                          <SelectItem value="OTHER">Other</SelectItem>
                        </SelectContent>
                      </Select>
                      {errors.gender && (
                        <p className="mt-1 text-sm text-red-500">{errors.gender.message}</p>
                      )}
                    </div>
                  </div>

                  <div>
                    <Label htmlFor="marital_status">Marital Status</Label>
                    <Select>
                      <SelectTrigger
                        id="marital_status"
                        className={errors.marital_status ? 'border-red-500' : ''}
                      >
                        <SelectValue placeholder="Select status" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="SINGLE">Single</SelectItem>
                        <SelectItem value="MARRIED">Married</SelectItem>
                        <SelectItem value="DIVORCED">Divorced</SelectItem>
                        <SelectItem value="WIDOWED">Widowed</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>
              )}

              {/* Step 2: Medical Information */}
              {step === 2 && (
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-gray-900">Medical Information</h3>

                  <div>
                    <Label htmlFor="allergies">Known Allergies</Label>
                    <Input
                      id="allergies"
                      placeholder="Enter allergies separated by commas"
                      {...register('allergies')}
                    />
                    <p className="mt-1 text-sm text-gray-500">
                      Enter multiple allergies separated by commas
                    </p>
                  </div>

                  <div>
                    <Label htmlFor="medications">Current Medications</Label>
                    <Input
                      id="medications"
                      placeholder="Enter medications separated by commas"
                      {...register('medications')}
                    />
                    <p className="mt-1 text-sm text-gray-500">
                      Enter multiple medications separated by commas
                    </p>
                  </div>

                  <div>
                    <Label htmlFor="address">Address</Label>
                    <Input id="address" placeholder="123 Main Street" {...register('address')} />
                  </div>

                  <div className="grid gap-4 md:grid-cols-2">
                    <div>
                      <Label htmlFor="city">City</Label>
                      <Input id="city" placeholder="New York" {...register('city')} />
                    </div>
                    <div>
                      <Label htmlFor="state">State/Province</Label>
                      <Input id="state" placeholder="NY" {...register('state')} />
                    </div>
                  </div>

                  <div className="grid gap-4 md:grid-cols-2">
                    <div>
                      <Label htmlFor="postal_code">Postal Code</Label>
                      <Input id="postal_code" placeholder="10001" {...register('postal_code')} />
                    </div>
                    <div>
                      <Label htmlFor="country">Country</Label>
                      <Input id="country" placeholder="United States" {...register('country')} />
                    </div>
                  </div>
                </div>
              )}

              {/* Step 3: Emergency Contact */}
              {step === 3 && (
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-gray-900">Emergency Contact Information</h3>

                  <div>
                    <Label htmlFor="emergency_contact_name">Emergency Contact Name</Label>
                    <Input
                      id="emergency_contact_name"
                      placeholder="Jane Doe"
                      {...register('emergency_contact_name')}
                    />
                  </div>

                  <div>
                    <Label htmlFor="emergency_contact_phone">Emergency Contact Phone</Label>
                    <Input
                      id="emergency_contact_phone"
                      type="tel"
                      placeholder="+1 (555) 987-6543"
                      {...register('emergency_contact_phone')}
                    />
                  </div>

                  <div>
                    <Label htmlFor="emergency_contact_relation">Relationship</Label>
                    <Input
                      id="emergency_contact_relation"
                      placeholder="Spouse / Parent / Sibling"
                      {...register('emergency_contact_relation')}
                    />
                  </div>

                  <div>
                    <Label htmlFor="insurance_provider">Insurance Provider</Label>
                    <Input
                      id="insurance_provider"
                      placeholder="Insurance Company Name"
                      {...register('insurance_provider')}
                    />
                  </div>

                  <div>
                    <Label htmlFor="insurance_policy_number">Insurance Policy Number</Label>
                    <Input
                      id="insurance_policy_number"
                      placeholder="Policy Number"
                      {...register('insurance_policy_number')}
                    />
                  </div>
                </div>
              )}

              {/* Step 4: Review */}
              {step === 4 && (
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-gray-900">Review & Confirm</h3>

                  <div className="rounded-lg bg-blue-50 p-4">
                    <p className="text-sm text-gray-700">
                      Please review the information you've provided. Ensure all details are accurate
                      before submitting.
                    </p>
                  </div>

                  <div className="flex items-start gap-3">
                    <Checkbox id="confirm" />
                    <Label htmlFor="confirm" className="text-sm">
                      I confirm that all the information provided is accurate and complete. I consent to
                      the medical treatment and data processing as per clinic policies.
                    </Label>
                  </div>
                </div>
              )}

              {/* Navigation Buttons */}
              <div className="flex justify-between gap-3 border-t pt-6">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setStep(Math.max(1, step - 1))}
                  disabled={step === 1 || isSubmitting}
                >
                  Previous
                </Button>

                {step < 4 ? (
                  <Button
                    type="button"
                    onClick={() => setStep(Math.min(4, step + 1))}
                    disabled={isSubmitting}
                  >
                    Next
                  </Button>
                ) : (
                  <Button type="submit" disabled={isSubmitting} className="gap-2">
                    {isSubmitting ? (
                      <>
                        <div className="h-4 w-4 animate-spin rounded-full border-2 border-white border-b-transparent"></div>
                        Registering...
                      </>
                    ) : (
                      <>
                        <Check className="h-4 w-4" />
                        Complete Registration
                      </>
                    )}
                  </Button>
                )}
              </div>
            </form>
          </CardContent>
        </Card>

        {/* Footer Info */}
        <div className="mt-6 text-center text-sm text-gray-600">
          <p>
            All medical information is treated with confidentiality and stored securely according to
            healthcare regulations.
          </p>
        </div>
      </div>
    </div>
  );
};

export default PatientRegistration;
