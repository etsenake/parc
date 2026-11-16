DEFAULTS = {"textdirection": "ltr", "language": "en", "fontfamily": "system-ui,sans-serif", "fontsize": "75%"}

TRY = "Try:"
CHECK_CONNECTION = "Checking the connection"
PROXY_FIREWALL = '<a href="#buttons" onclick="toggleHelpBox()">Checking the proxy and the firewall</a>'
PROXY_FIREWALL_DNS = '<a href="#buttons" onclick="toggleHelpBox()">Checking the proxy, firewall, and DNS configuration</a>'
CONNECTION_DETAILS = [
    {"header": "Check your Internet connection",
     "body": "Check any cables and reboot any routers, modems, or other network devices you may be using."},
    {"header": "Allow Parc to access the network in your firewall or antivirus settings.",
     "body": "If it is already listed as a program allowed to access the network, try removing it from the list and adding it again."},
    {"header": "If you use a proxy server…",
     "body": "Check your proxy settings or contact your network administrator to make sure the proxy server is working."},
]
DINO = {
    "dinoGameA11yAriaLabel": "", "dinoGameInstructionsTouch": "Tap the dino to play",
    "dinoGameInstructionsKeyboard": "Press space to play",
    "dinoGameInstructionsHybrid": "Tap the dino or press space to play",
    "dinoGameA11yAriaLabelTouch": "", "dinoGameA11yAriaLabelKeyboard": "", "dinoGameA11yAriaLabelHybrid": "",
}


def net(code, host, heading, summary, *, url=None, tries=None, details=None, reload=True, icon="icon-generic",
        title=None, **extra):
    data = dict(DEFAULTS, title=title or host, iconClass=icon, heading={"msg": heading}, summary={"msg": summary},
                errorCode=code, details="Details", hideDetails="Hide details", isOfflineError=False)
    if tries:
        data["suggestionsSummaryListHeader"] = TRY
        data["suggestionsSummaryList"] = [{"summary": item} for item in tries]
    if details:
        data["suggestionsDetails"] = details
    if reload:
        data["reloadButton"] = {"msg": "Reload", "reloadUrl": url or f"https://{host}/"}
    data.update(extra)
    return data


def strong(host):
    return f"<strong>{host}</strong>"


NOT_AVAILABLE = "This site can’t be reached"
NOT_WORKING = "This page isn’t working"

NET = {
    "refused": net("ERR_CONNECTION_REFUSED", "studio.example.com", NOT_AVAILABLE,
                   f"{strong('studio.example.com')} refused to connect.",
                   tries=[CHECK_CONNECTION, PROXY_FIREWALL], details=CONNECTION_DETAILS),
    "reset": net("ERR_CONNECTION_RESET", "studio.example.com", NOT_AVAILABLE, "The connection was reset.",
                 tries=[CHECK_CONNECTION, PROXY_FIREWALL], details=CONNECTION_DETAILS),
    "empty": net("ERR_EMPTY_RESPONSE", "studio.example.com", NOT_WORKING,
                 f"{strong('studio.example.com')} didn’t send any data.", tries=["Try reloading the page."]),
    "offline": dict(net("ERR_INTERNET_DISCONNECTED", "example.com", "No internet", "No internet",
                        tries=["Checking the network cables, modem, and router", "Reconnecting to Wi-Fi"],
                        reload=False, icon="icon-offline", isOfflineError=True), **DINO),
    "offline-quiet": dict(net("ERR_INTERNET_DISCONNECTED", "example.com", "No internet", "No internet",
                              reload=False, icon="icon-offline", isOfflineError=True,
                              disabledEasterEgg="The fun is disabled."), **DINO),
    "dino": dict(DEFAULTS, title="chrome://dino/", iconClass="icon-offline", heading={"msg": "Press space to play"},
                 errorCode="", isOfflineError=True, **DINO),
    "dns-started": net("DNS_PROBE_STARTED", "exmaple.com", NOT_AVAILABLE,
                       f"{strong('exmaple.com')}’s <abbr id=\"dnsDefinition\">DNS address</abbr> could not be found. Diagnosing the problem.",
                       tries=[CHECK_CONNECTION]),
    "dns": net("DNS_PROBE_FINISHED_NXDOMAIN", "exmaple.com", NOT_AVAILABLE,
               f"{strong('exmaple.com')}’s server IP address could not be found.",
               tries=[CHECK_CONNECTION, PROXY_FIREWALL_DNS], details=CONNECTION_DETAILS),
    "timed-out": net("ERR_CONNECTION_TIMED_OUT", "slow.example.org", NOT_AVAILABLE,
                     f"{strong('slow.example.org')} took too long to respond.",
                     tries=[CHECK_CONNECTION, PROXY_FIREWALL], details=CONNECTION_DETAILS),
    "redirects": net("ERR_TOO_MANY_REDIRECTS", "loop.example.com", NOT_WORKING,
                     f"{strong('loop.example.com')} redirected you too many times.",
                     tries=['<a href="https://support.google.com/chrome?p=rl_error">Try deleting your cookies</a>.']),
    "not-found-404": net("HTTP ERROR 404", "shop.example.com", f"This {strong('shop.example.com')} page can’t be found",
                         f"No webpage was found for the web address: {strong('https://shop.example.com/old')}",
                         url="https://shop.example.com/old"),
    "server-500": net("HTTP ERROR 500", "api.example.com", NOT_WORKING,
                      f"{strong('api.example.com')} is currently unable to handle this request."),
    "file-missing": net("ERR_FILE_NOT_FOUND", "", "Your file couldn’t be accessed", "It may have been moved, edited, or deleted.",
                        title="file:///Users/me/Notes/plan.html", url="file:///Users/me/Notes/plan.html"),
    "extension": net("ERR_BLOCKED_BY_CLIENT", "ads.example.com", f"{strong('ads.example.com')} is blocked",
                     "This page has been blocked by an extension", tries=["Try disabling your extensions."]),
    "admin": net("ERR_BLOCKED_BY_ADMINISTRATOR", "games.example.com", f"{strong('games.example.com')} is blocked",
                 "Your organization doesn’t allow you to view this site", reload=False, icon="icon-info",
                 details=[{"header": "Check your administrator's policies",
                           "body": "Visit <strong>chrome://policy</strong> to see the list of blocked URLs and other policies enforced by your system administrator."}]),
    "framed": net("ERR_BLOCKED_BY_RESPONSE", "maps.example.com", f"{strong('maps.example.com')} refused to connect.",
                  f"{strong('maps.example.com')} refused to connect.", reload=False),
    "resubmit": net("ERR_CACHE_MISS", "checkout.example.com", "Confirm Form Resubmission",
                    "This webpage requires data that you entered earlier in order to be properly displayed. You can send this data again, but by doing so you will repeat any action this page previously performed.",
                    tries=["Press the reload button to resubmit the data needed to load the page."], reload=False),
    "cache-read": net("ERR_CACHE_MISS", "news.example.com", "This site can’t be loaded from the cache",
                      "The page you are looking for used information that you entered.", tries=["Try reloading the page."]),
    "bad-address": net("ERR_INVALID_URL", "", NOT_AVAILABLE,
                       f"The webpage at {strong('chrome://nope/')} might be temporarily down or it may have moved permanently to a new web address.",
                       title="chrome://nope/", url="chrome://nope/"),
    "secure-failed": net("ERR_SSL_PROTOCOL_ERROR", "old.example.com", "This site can’t provide a secure connection",
                         f"{strong('old.example.com')} sent an invalid response.", tries=["Try running Network Diagnostics."]),
    "unknown-code": net("ERR_HTTP2_PROTOCOL_ERROR", "cdn.example.com", NOT_WORKING,
                        f"{strong('cdn.example.com')} sent an invalid response.", tries=["Try reloading the page."]),
}

SSL_DEBUG = {"subject": "bank.example.com", "issuer": "Example Untrusted CA", "expirationDate": "11/30/27",
             "currentDate": "11/16/26", "pem": "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----", "ct": ""}

BASE = dict(DEFAULTS, displaycheckbox=False, boxchecked=False, displayEnhancedProtectionMessage=False,
            optInLink="Help improve security on the web for everyone by sending <a href=\"#\" id=\"whitepaper-link\">URLs of some pages you visit, limited system information, and some page content</a> to Google. <a href=\"#\" id=\"privacy-link\">Privacy policy</a>",
            enhancedProtectionMessage="<a href=\"#\" id=\"enhanced-protection-link\">Turn on enhanced protection</a> to get Parc’s highest level of security",
            openDetails="Details", closeDetails="Hide details", explanationParagraph="", finalParagraph="")


def warning(kind, **values):
    return dict(BASE, type=kind, **values)


LEARN = '<a href="#" id="learn-more-link">Learn more about this warning</a>'

INTERSTITIALS = {
    "ssl": warning("SSL", bad_clock=False, is_qwac_enabled=False, overridable=True, hide_primary_button=False,
                   errorCode="NET::ERR_CERT_AUTHORITY_INVALID", tabTitle="Privacy error",
                   heading="Your connection is not private",
                   primaryParagraph=f"Attackers might be trying to steal your information from <strong>bank.example.com</strong> (for example, passwords, messages, or credit cards). {LEARN}",
                   explanationParagraph="This server could not prove that it is <strong>bank.example.com</strong>; its security certificate is not trusted by your computer's operating system. This may be caused by a misconfiguration or an attacker intercepting your connection.",
                   finalParagraph='<a href="#" id="proceed-link">Proceed to bank.example.com (unsafe)</a>',
                   openDetails="Advanced", closeDetails="Hide advanced", primaryButtonText="Back to safety", **SSL_DEBUG),
    "ssl-hsts": warning("SSL", bad_clock=False, is_qwac_enabled=False, overridable=False, hide_primary_button=False,
                        errorCode="NET::ERR_CERT_DATE_INVALID", errorType=2, tabTitle="Privacy error",
                        heading="Your connection is not private",
                        primaryParagraph=f"Attackers might be trying to steal your information from <strong>mail.example.com</strong> (for example, passwords, messages, or credit cards). {LEARN}",
                        explanationParagraph="<strong>mail.example.com</strong> normally uses encryption to protect your information.",
                        finalParagraph="You cannot visit <strong>mail.example.com</strong> right now because the website uses HSTS. Network errors and attacks are usually temporary, so this page will probably work later.",
                        openDetails="Advanced", closeDetails="Hide advanced", primaryButtonText="Reload", **SSL_DEBUG),
    "bad-clock": warning("SSL", bad_clock=True, overridable=False, hide_primary_button=False, tabTitle="Clock error",
                         heading="Your clock is behind",
                         primaryParagraph="A private connection to <strong>bank.example.com</strong> can't be established because your computer's date and time (Monday, November 16, 2026) are incorrect.",
                         explanationParagraph="To establish a secure connection, your clock needs to be set correctly.",
                         primaryButtonText="Update date and time", errorCode="NET::ERR_CERT_DATE_INVALID", **SSL_DEBUG),
    "mitm": warning("SSL", bad_clock=False, overridable=False, hide_primary_button=True, disableKeyboardOverride=True,
                    tabTitle="Privacy error", heading="An application is stopping Parc from safely connecting to this site",
                    primaryParagraph="“Example Shield” isn’t installed properly on your computer or network.",
                    primaryButtonText="", errorCode="NET::ERR_CERT_AUTHORITY_INVALID", **SSL_DEBUG),
    "safe-browsing": warning("SAFEBROWSING", billing=False, phishing=True, overridable=True, hide_primary_button=False,
                             tabTitle="Security error", heading="Dangerous site", displaycheckbox=True,
                             primaryParagraph=f"Attackers on the site you tried visiting might trick you into installing software or revealing things like your passwords, phone, or credit card numbers. Parc strongly recommends going back to safety. {LEARN}",
                             explanationParagraph='Parc has built-in safety features to protect you while you browse — like Google Safe Browsing, which <a href="#" id="diagnostic-link">recently found phishing</a> on the site you tried visiting. <a href="#" id="report-error-link">Let us know</a> if you think there’s been a mistake.',
                             finalParagraph='If you understand the risks to your security, you may <a href="#" id="proceed-link">visit this unsafe site</a>.',
                             primaryButtonText="Back to safety"),
    "malware": warning("SAFEBROWSING", billing=False, phishing=False, overridable=False, hide_primary_button=False,
                       tabTitle="Security error", heading="Dangerous site",
                       primaryParagraph=f"Attackers on the site you tried visiting might install harmful software that steals or deletes things like your passwords, photos, messages, or credit card numbers. Parc strongly recommends going back to safety. {LEARN}",
                       explanationParagraph="Parc has built-in safety features to protect you while you browse.",
                       primaryButtonText="Back to safety"),
    "billing": warning("SAFEBROWSING", billing=True, phishing=False, overridable=True, hide_primary_button=False,
                       tabTitle="Security error", heading="The page ahead may try to charge you money",
                       primaryParagraph="These charges could be one-time or recurring and may not be obvious.",
                       proceedButtonText="Proceed", primaryButtonText="Go back"),
    "lookalike": warning("LOOKALIKE", overridable=False, hide_primary_button=False, tabTitle="Fake site warning",
                         heading='Did you mean <a href="#" id="dont-proceed-link">example.com</a>?',
                         primaryParagraph="The site you just tried to visit looks fake. Attackers sometimes mimic sites by making small, hard-to-see changes to the URL.",
                         proceedButtonText="Ignore", primaryButtonText="Go to example.com",
                         lookalikeConsoleMessage="Parc flagged this as a lookalike."),
    "https-only": warning("HTTPS_ONLY", overridable=False, hide_primary_button=False, tabTitle="Site is not secure",
                          heading="The connection to <strong>legacy.example.com</strong> is not secure",
                          primaryParagraph=f"You are seeing this warning because this site does not support HTTPS. {LEARN}",
                          proceedButtonText="Continue to site", primaryButtonText="Go back"),
    "insecure-form": warning("INSECURE_FORM", overridable=False, hide_primary_button=False, tabTitle="Form is not secure",
                             heading="The information you’re about to submit is not secure",
                             primaryParagraph="Because this site is using a connection that’s not completely secure, your information will be visible to others.",
                             proceedButtonText="Send anyway", primaryButtonText="Go back"),
    "captive-portal": warning("CAPTIVE_PORTAL", overridable=False, hide_primary_button=False, tabTitle="Connect to Wi-Fi",
                              heading="Connect to Wi-Fi",
                              primaryParagraph="The Wi-Fi you’re using (<strong>Cafe Guest</strong>) may require you to visit its login page.",
                              primaryButtonText="Connect"),
    "lookalike-fake": warning("LOOKALIKE", overridable=False, hide_primary_button=False, tabTitle="Safety warning",
                              heading="Fake site ahead",
                              primaryParagraph="Attackers sometimes mimic sites by making small, hard-to-see changes to the URL.",
                              proceedButtonText="Ignore", primaryButtonText="Back to safety",
                              lookalikeConsoleMessage="Parc flagged this as a lookalike."),
    "https-engagement": warning("HTTPS_ONLY", overridable=False, hide_primary_button=False, tabTitle="Site is not secure",
                                heading="The connection to bank.example.com is not secure",
                                primaryParagraph=f"You usually connect to this site securely, but Parc couldn't use a secure connection this time. An attacker might be trying to eavesdrop or modify your network connection. {LEARN}",
                                proceedButtonText="Continue to site", primaryButtonText="Go back"),
    "blocked-interception": warning("BLOCKED_INTERCEPTION", overridable=True, hide_primary_button=False, bad_clock=False,
                                    tabTitle="Your activity on mail.example.com is being monitored",
                                    heading="Your activity on mail.example.com is being monitored",
                                    primaryParagraph="Anything you type, any pages you view, or any other activity on the web is being watched. Content on sites may be changed without your knowledge.",
                                    explanationParagraph="This problem happens because of a certificate you or someone else installed on your device.",
                                    finalParagraph='<a href="#" id="proceed-link">Proceed to mail.example.com (unsafe)</a>',
                                    primaryButtonText="Back to safety"),
    "enterprise-warn": warning("ENTERPRISE_WARN", overridable=False, hide_primary_button=False, tabTitle="Admin warning",
                               heading="The site ahead is flagged by your organization",
                               primaryParagraph=f"Your organization has identified <strong>games.example.com</strong> as a site that might violate a policy. {LEARN}",
                               proceedButtonText="Continue to site", primaryButtonText="Go back"),
    "enterprise-block-domain": warning("ENTERPRISE_BLOCK", overridable=False, hide_primary_button=False,
                                       tabTitle="Blocked by Admin", heading="The site ahead is blocked by your organization",
                                       primaryParagraph=f"Your organization has blocked <strong>games.example.com</strong> because it violates a policy. {LEARN}",
                                       primaryButtonText="Go back"),
    "enterprise-block": warning("ENTERPRISE_BLOCK", overridable=False, hide_primary_button=False,
                                tabTitle="Site blocked", heading="Your organization doesn’t allow you to view this site",
                                primaryParagraph="Your administrator manages this browser. See chrome://management for details.",
                                primaryButtonText="Go back"),
}

