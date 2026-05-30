<#import "field.ftl" as field>
<#macro username>
  <#assign label>
    <#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if>
  </#assign>
  <@field.group name="username" label=label>
    <div class="${properties.kcInputGroup}">
      <div class="${properties.kcInputGroupItemClass} ${properties.kcFill}">
        <span class="${properties.kcInputClass} ${properties.kcFormReadOnlyClass}">
          <input id="kc-attempted-username" value="${auth.attemptedUsername}" readonly>
        </span>
      </div>
      <div class="${properties.kcInputGroupItemClass}">
        <button id="reset-login" class="${properties.kcFormPasswordVisibilityButtonClass} kc-login-tooltip" type="button"
              aria-label="${msg('restartLoginTooltip')}" onclick="location.href='${url.loginRestartFlowUrl}'">
            <i class="fa-sync-alt fas" aria-hidden="true"></i>
            <span class="kc-tooltip-text">${msg("restartLoginTooltip")}</span>
        </button>
      </div>
    </div>
  </@field.group>
</#macro>

<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}"<#if realm.internationalizationEnabled> lang="${locale.currentLanguageTag}"</#if>>

<head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <meta name="robots" content="noindex, nofollow">

    <#if properties.meta?has_content>
        <#list properties.meta?split(' ') as meta>
            <meta name="${meta?split('==')[0]}" content="${meta?split('==')[1]}"/>
        </#list>
    </#if>
    <title>${msg("loginTitle",(realm.displayName!''))}</title>
    <link rel="icon" type="image/png" href="${url.resourcesPath}/img/planvault-icon.png" />
    <#if properties.stylesCommon?has_content>
        <#list properties.stylesCommon?split(' ') as style>
            <link href="${url.resourcesCommonPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <script type="importmap">
        {
            "imports": {
                "rfc4648": "${url.resourcesCommonPath}/vendor/rfc4648/rfc4648.js"
            }
        }
    </script>
    <#if properties.scripts?has_content>
        <#list properties.scripts?split(' ') as script>
            <script src="${url.resourcesPath}/${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <#if scripts??>
        <#list scripts as script>
            <script src="${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <script type="module" src="${url.resourcesPath}/js/passwordVisibility.js"></script>
    <script type="module">
        <#outputformat "JavaScript">
        import { startSessionPolling } from "${url.resourcesPath}/js/authChecker.js";

        startSessionPolling(
            ${url.ssoLoginInOtherTabsUrl?c}
        );
        </#outputformat>
    </script>
    <script>
        (function () {
            var CLS = "pf-v5-theme-dark";
            var CK = "planvault_kc_theme";

            function readCookieTheme() {
                try {
                    var m = document.cookie.match(new RegExp("(?:^|; )" + CK + "=(light|dark)(?:;|$)"));
                    if (m) return m[1] === "dark";
                } catch (e) {}
                return null;
            }

            function applyInitial() {
                var q = new URLSearchParams(window.location.search);
                var qt = q.get("pv_theme");
                var dark = null;
                if (qt === "dark") dark = true;
                if (qt === "light") dark = false;
                if (dark === null) {
                    var c = readCookieTheme();
                    if (c !== null) dark = c;
                }
                if (dark === null) {
                    dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
                }
                document.documentElement.classList.toggle(CLS, dark);
            }

            function applyFromCookieOrSystem() {
                var c = readCookieTheme();
                var mq = window.matchMedia("(prefers-color-scheme: dark)");
                var dark = mq.matches;
                if (c !== null) dark = c;
                document.documentElement.classList.toggle(CLS, dark);
            }

            window.pvApplyKeycloakTheme = applyFromCookieOrSystem;
            applyInitial();
            window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
                if (readCookieTheme() === null) applyFromCookieOrSystem();
            });

            window.pvSyncPlanvaultDomainThemeCookie = function (mode) {
                var host = location.hostname;
                var maxAge = 86400 * 400;
                var secure = location.protocol === "https:";
                var c;
                if (host === "planvault.ai" || host.endsWith(".planvault.ai")) {
                    c = CK + "=" + mode + "; Path=/; Domain=.planvault.ai; Max-Age=" + maxAge + "; SameSite=Lax" + (secure ? "; Secure" : "");
                } else if (host === "localhost" || host === "127.0.0.1") {
                    c = CK + "=" + mode + "; Path=/; Max-Age=" + maxAge + "; SameSite=Lax" + (secure ? "; Secure" : "");
                } else {
                    return;
                }
                document.cookie = c;
            };
        })();
    </script>
</head>

<body id="keycloak-bg" class="${properties.kcBodyClass!}">

<header class="pv-top-nav" role="banner">
    <div class="pv-top-nav__toolbar">
        <a class="pv-top-nav__brand" href="/" id="pv-site-root">
            <img src="${url.resourcesPath}/img/planvault-icon.png" width="32" height="32" alt="" />
            <span class="pv-top-nav__title">${realm.displayName!''}</span>
        </a>
        <div class="pv-top-nav__actions">
            <#if realm.internationalizationEnabled && locale.supported?size gt 1>
            <label class="pv-visually-hidden" for="pv-lang-select">${msg('pvLangSwitchAria')}</label>
            <select id="pv-lang-select" class="pv-lang-select" title="${msg('pvLangSwitchAria')}" aria-label="${msg('pvLangSwitchAria')}" onchange="if (this.value) window.location.href=this.value">
                <#list locale.supported?sort_by("label") as l>
                <option value="${l.url}"<#if l.languageTag == locale.currentLanguageTag> selected="selected"</#if>>${l.label}</option>
                </#list>
            </select>
            </#if>
            <button type="button" class="pv-top-nav__icon-btn" id="pv-theme-toggle" title="${msg('pvThemeToggle')}" aria-label="${msg('pvThemeToggle')}">
                <svg class="pv-top-nav__icon pv-top-nav__icon--moon" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 3a9 9 0 1 0 9 9c0-.46-.04-.92-.1-1.36a5.389 5.389 0 0 1-4.4 2.26 5.403 5.403 0 0 1-3.14-9.8c.44-.06.9-.1 1.36-.1z"/></svg>
                <svg class="pv-top-nav__icon pv-top-nav__icon--sun" width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10zM2 13h2v-2H2v2zm18 0h2v-2h-2v2zM11 2v2h2V2h-2zm0 18v2h2v-2h-2zM4.93 4.93l1.41 1.41 1.42-1.41-1.42-1.41L4.93 4.93zm12.73 12.73l1.41 1.41 1.42-1.41-1.42-1.41-1.41 1.41zM19.07 4.93l-1.41 1.41 1.41 1.42 1.42-1.41-1.42-1.42zM6.34 17.66l-1.41 1.41 1.41 1.42 1.42-1.41-1.42-1.42z"/></svg>
            </button>
        </div>
    </div>
</header>

<div class="pv-page-body">
<div class="pv-login-stage">
<div class="pv-login-shell">
<div class="${properties.kcLogin!}">
  <div class="${properties.kcLoginContainer!}">
    <#-- Default Keycloak header sits in a wide-layout column and shows the realm name beside the card; hide it — brand is in pv-top-nav. -->
    <div id="kc-header" class="pf-v5-c-login__header pv-kc-header--skip" aria-hidden="true">
      <div id="kc-header-wrapper" class="pf-v5-c-brand"></div>
    </div>
    <main class="${properties.kcLoginMain!}">
      <div class="${properties.kcLoginMainHeader!}">
        <h1 class="${properties.kcLoginMainTitle!}" id="kc-page-title"><#nested "header"></h1>
        <#if realm.internationalizationEnabled  && locale.supported?size gt 1>
        <div class="${properties.kcLoginMainHeaderUtilities!}">
          <div class="${properties.kcInputClass!}">
            <select
              aria-label="${msg("languages")}"
              id="login-select-toggle"
              onchange="if (this.value) window.location.href=this.value"
            >
              <#list locale.supported?sort_by("label") as l>
                <option
                  value="${l.url}"
                  ${(l.languageTag == locale.currentLanguageTag)?then('selected','')}
                >
                  ${l.label}
                </option>
              </#list>
            </select>
            <span class="${properties.kcFormControlUtilClass}">
              <span class="${properties.kcFormControlToggleIcon!}">
                <svg
                  class="pf-v5-svg"
                  viewBox="0 0 320 512"
                  fill="currentColor"
                  aria-hidden="true"
                  role="img"
                  width="1em"
                  height="1em"
                >
                  <path
                    d="M31.3 192h257.3c17.8 0 26.7 21.5 14.1 34.1L174.1 354.8c-7.8 7.8-20.5 7.8-28.3 0L17.2 226.1C4.6 213.5 13.5 192 31.3 192z"
                  >
                  </path>
                </svg>
              </span>
            </span>
          </div>
        </div>
        </#if>
      </div>
      <div class="${properties.kcLoginMainBody!}">
        <#if !(auth?has_content && auth.showUsername() && !auth.showResetCredentials())>
            <#if displayRequiredFields>
                <div class="${properties.kcContentWrapperClass!}">
                    <div class="${properties.kcLabelWrapperClass!} subtitle">
                        <span class="${properties.kcInputHelperTextItemTextClass!}">
                          <span class="${properties.kcInputRequiredClass!}">*</span> ${msg("requiredFields")}
                        </span>
                    </div>
                </div>
            </#if>
        <#else>
            <#if displayRequiredFields>
                <div class="${properties.kcContentWrapperClass!}">
                    <div class="${properties.kcLabelWrapperClass!} subtitle">
                        <span class="${properties.kcInputHelperTextItemTextClass!}">
                          <span class="${properties.kcInputRequiredClass!}">*</span> ${msg("requiredFields")}
                        </span>
                    </div>
                    <div class="${properties.kcFormClass} ${properties.kcContentWrapperClass}">
                        <#nested "show-username">
                        <@username />
                    </div>
                </div>
            <#else>
                <div class="${properties.kcFormClass} ${properties.kcContentWrapperClass}">
                  <#nested "show-username">
                  <@username />
                </div>
            </#if>
        </#if>

        <#-- App-initiated actions should not see warning messages about the need to complete the action during login. -->
        <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
            <div class="${properties.kcAlertClass!} pf-m-${(message.type = 'error')?then('danger', message.type)}">
                <div class="${properties.kcAlertIconClass!}">
                    <#if message.type = 'success'><span class="${properties.kcFeedbackSuccessIcon!}"></span></#if>
                    <#if message.type = 'warning'><span class="${properties.kcFeedbackWarningIcon!}"></span></#if>
                    <#if message.type = 'error'><span class="${properties.kcFeedbackErrorIcon!}"></span></#if>
                    <#if message.type = 'info'><span class="${properties.kcFeedbackInfoIcon!}"></span></#if>
                </div>
                <span class="${properties.kcAlertTitleClass!} kc-feedback-text">${kcSanitize(message.summary)?no_esc}</span>
            </div>
        </#if>

        <#nested "form">

        <#if auth?has_content && auth.showTryAnotherWayLink()>
          <form id="kc-select-try-another-way-form" action="${url.loginAction}" method="post" novalidate="novalidate">
              <input type="hidden" name="tryAnotherWay" value="on"/>
              <a id="try-another-way" href="javascript:document.forms['kc-select-try-another-way-form'].submit()"
                  class="${properties.kcButtonSecondaryClass} ${properties.kcButtonBlockClass} ${properties.kcMarginTopClass}">
                    ${kcSanitize(msg("doTryAnotherWay"))?no_esc}
              </a>
          </form>
        </#if>

        <#if displayInfo>
          <div id="kc-info" class="${properties.kcSignUpClass!}">
              <div id="kc-info-wrapper" class="${properties.kcInfoAreaWrapperClass!}">
                  <#nested "info">
              </div>
          </div>
        </#if>
      </div>
      <div class="pf-v5-c-login__main-footer">
        <#nested "socialProviders">
      </div>
    </main>
  </div>
</div>
</div>
</div>

<footer class="pv-page-footer" role="contentinfo">
    <nav class="pv-page-footer__nav" aria-label="${msg('pvFooterAriaLabel')}">
        <a class="pv-page-footer__link" href="/support" data-pv-path="/support">${msg("pvFooterSupport")}</a>
        <span class="pv-page-footer__sep" aria-hidden="true">·</span>
        <a class="pv-page-footer__link" href="/privacy" data-pv-path="/privacy">${msg("pvFooterPrivacy")}</a>
        <span class="pv-page-footer__sep" aria-hidden="true">·</span>
        <a class="pv-page-footer__link" href="/cookies" data-pv-path="/cookies">${msg("pvFooterCookies")}</a>
        <span class="pv-page-footer__sep" aria-hidden="true">·</span>
        <a class="pv-page-footer__link" href="/docs" data-pv-path="/docs">${msg("pvNavDocs")}</a>
        <span class="pv-page-footer__sep" aria-hidden="true">·</span>
        <a class="pv-page-footer__link" href="/api-docs" data-pv-path="/api-docs">${msg("pvNavApiDocs")}</a>
        <span class="pv-page-footer__sep" aria-hidden="true">·</span>
        <a class="pv-page-footer__link" href="/support" data-pv-path="/support">${msg("pvNavContact")}</a>
    </nav>
    <p class="pv-page-footer__meta">
        ${msg("pvAuthPoweredBy")}<a class="pv-page-footer__meta-link" href="https://www.keycloak.org/" target="_blank" rel="noopener noreferrer">Keycloak</a>${msg("pvAuthPoweredBySuffix")}
    </p>
</footer>
</div>

<script>
(function () {
    var site = window.location.origin;
    var root = document.getElementById("pv-site-root");
    if (root) root.href = site + "/";
    document.querySelectorAll("a[data-pv-path]").forEach(function (a) {
        var p = a.getAttribute("data-pv-path");
        if (p) a.href = site + p;
    });
})();
(function () {
    var CLS = "pf-v5-theme-dark";
    var btn = document.getElementById("pv-theme-toggle");
    if (!btn) return;
    btn.addEventListener("click", function () {
        var root = document.documentElement;
        var next = !root.classList.contains(CLS);
        root.classList.toggle(CLS, next);
        var mode = next ? "dark" : "light";
        if (typeof window.pvSyncPlanvaultDomainThemeCookie === "function") {
            window.pvSyncPlanvaultDomainThemeCookie(mode);
        }
    });
})();
</script>
</body>
</html>
</#macro>
