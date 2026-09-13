// Compatibility declarations for legacy components that reference the React namespace
// while the application uses the automatic JSX runtime.
declare global {
  namespace React {
    type ElementType = import('react').ElementType;
    type ReactNode = import('react').ReactNode;
    type FormEvent = import('react').FormEvent;
  }
}

export {}; 
