# Airline logo source

The airline ranking uses the public PNG endpoint described in the
[Travelpayouts mobile API documentation](https://support.travelpayouts.com/hc/en-us/articles/203956153-API-for-mobile-apps):

`https://pics.avs.io/144/144/{IATA}.png`

Only recognized two-character IATA codes from the app's airline catalog are
requested. Airline names, flight histories and other user-entered fields are
not sent. Like other remote image requests, the CDN can see the requested code
and standard connection information such as the device's IP address.

Logos retain their original color and aspect ratio on a circular neutral light
plate, with inset padding that preserves the complete brand mark.
When a ranking row requests a matching accent, the widget samples at most 1,024
pixels from that same decoded image, excluding transparent, neutral and very
dark pixels, and reports its dominant colored hue. The derived color is kept
only in memory by IATA code; extraction does not make another network request.
Loading failures, missing logos and offline use fall back to the airline code;
unknown or malformed codes do not trigger a request. Flutter may retain decoded
images in its ordinary in-memory image cache. There is no bundled logo dataset
or persistent disk cache in this implementation.

The documentation notes that some airlines have no logo. It documents image
retrieval, but does not establish blanket rights to redistribute all airlines'
trademarks or to bundle an offline dataset. Confirm applicable provider and
brand permissions before public distribution, persistent caching or bundling.
This implementation does not use Airhex demo images.

Endpoint availability was checked on 2026-10-13 with HEAD requests for CA and
HU; both returned HTTP 200. This is not a guarantee of future availability or
complete logo coverage.
