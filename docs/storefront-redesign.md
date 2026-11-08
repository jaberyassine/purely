# Purely storefront redesign

The home page, collections, catalog, search, shopping bag, checkout and account
styles use a cream and forest-green palette with serif headings. Product cards
use the real product photo URLs already stored through the admin APIs. No
reviews, delivery guarantees or payment capabilities are invented.

Catalog filters resolve categories from the URL and fetched data, including on
refresh. Sorting changes the visible order without mutating the fetched list.
Search covers product names, collections and descriptions. Loading, unavailable
photos and empty results have explicit states. The shopping bag supports keyboard
focus containment and Escape, and shows a sign-in action when empty/anonymous.

Browser API calls now use `Bearer <token>` with a space. Credential and response
debug logging was removed. Failed checkout requests keep the bag and stay on the
form; only a successful API response navigates to order confirmation.

## Preview

Run `Show-PurelyRedesign.ps1` in the operator workspace, then open
`http://127.0.0.1:5191/`. The helper synchronizes reviewed Desktop source with a
verified backup, runs tests/build, and starts a loopback-only development server.
Its HTTPS proxy points to the existing public Purely API; account, bag and order
actions in this preview operate on the demo backend. Keep the terminal open.
Ctrl+C stops the preview. No image is published and no AKS deployment is changed.

## Validation and release

`npm test` checks refreshed collection routes, numeric sorting, immutable source
order, search, and unknown collections. `npm run build` verifies production
bundling. Local React render checks also passed for the hero, navigation,
accessible search, empty bag and product cards. Browser visual and interaction
checks remain pending because the automated browser could not reach the local
preview server. Check desktop/mobile, sign-in, add/remove quantity and checkout
before publishing. All existing Sonar and image scan gates remain required for
the subsequent approved release and GitOps image update.
