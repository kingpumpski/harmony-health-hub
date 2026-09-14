import Encounters from './Encounters';

/**
 * Compatibility route for the legacy consultation URL.
 * The authoritative encounter workflow lives in Encounters; keeping this route
 * as a thin alias prevents two competing clinical documentation workflows.
 */
export default Encounters;
