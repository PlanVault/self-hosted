<#-- Text-only IdP links (no icons), centered. No "Or sign in with" band. -->
<#macro show social>
  <div id="kc-social-providers" class="${properties.kcFormSocialAccountSectionClass!}">
      <ul class="${properties.kcFormSocialAccountListClass!} <#if social.providers?size gt 3>${properties.kcFormSocialAccountListGridClass!}</#if>">
          <#list social.providers as p>
              <#assign pvSocialLabel>${msg("pvSignInWithPrefix")} ${p.displayName!""}</#assign>
              <li class="${properties.kcFormSocialAccountListItemClass!}">
                  <a data-once-link data-disabled-class="${properties.kcFormSocialAccountListButtonDisabledClass!}" id="social-${p.alias}"
                          class="${properties.kcFormSocialAccountListButtonClass!} pv-social-idp-text-only <#if social.providers?size gt 3>${properties.kcFormSocialAccountGridItem!}</#if>"
                          aria-label="${pvSocialLabel}" type="button" href="${p.loginUrl}">
                      <span class="${properties.kcFormSocialAccountNameClass!}">${pvSocialLabel}</span>
                  </a>
              </li>
          </#list>
      </ul>
  </div>
</#macro>
