class Env {
  static const bool useFirestoreForDailyHues = true;

  // Cloud Function that 302-redirects to Stripe Checkout
  // TODO: paste your deployed Functions URL:
  static const String checkoutRedirectUrl =
      'https://us-central1-YOUR_PROJECT.cloudfunctions.net/checkoutRedirect';
}
