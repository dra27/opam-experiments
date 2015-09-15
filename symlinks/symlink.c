#include <stdio.h>

#define UNICODE
#include <Windows.h>
#include <NTSecAPI.h>
#include <SubAuth.h>
#include <Sddl.h>

#define luid_eq(l, r) (l.LowPart == r.LowPart && l.HighPart == r.HighPart)
#define PLURAL(count) (count == 1 ? "" : "s")

// NTSecAPI.h seems to be missing this (at least in the Windows 7 SDK)
#ifndef LSA_LOOKUP_ISOLATED_AS_LOCAL
#define LSA_LOOKUP_ISOLATED_AS_LOCAL 0x80000000
#endif

int main(void)
{
  // GetCurrentProcess cannot fail
  HANDLE hProcess = GetCurrentProcess();

  if (OpenProcessToken(hProcess, TOKEN_READ, &hProcess))
  {
    LUID seCreateSymbolicLinkPrivilege;

    if (LookupPrivilegeValue(NULL, SE_CREATE_SYMBOLIC_LINK_NAME, &seCreateSymbolicLinkPrivilege))
    {
      DWORD length;

      printf("SeCreateSymbolicLinkPrivilege = %ld, %ld\n", seCreateSymbolicLinkPrivilege.HighPart, seCreateSymbolicLinkPrivilege.LowPart);

      if (!GetTokenInformation(hProcess, TokenPrivileges, NULL, 0, &length))
      {
        if (GetLastError() == ERROR_INSUFFICIENT_BUFFER)
        {
          TOKEN_PRIVILEGES* privileges = (TOKEN_PRIVILEGES*)malloc(length);
          if (GetTokenInformation(hProcess, TokenPrivileges, privileges, length, &length))
          {
            BOOL found = FALSE;
            DWORD count = privileges->PrivilegeCount;

            printf("User has %ld privileges\n", count);

            if (count > 0)
            {
              LUID_AND_ATTRIBUTES* privs = privileges->Privileges;
              while (count-- > 0 && !luid_eq(privs->Luid, seCreateSymbolicLinkPrivilege))
                privs++;
              found = (count > 0);
            }

            printf("User does%s have the SeCreateSymbolicLinkPrivilege\n", (found ? "" : "n't"));
          }
          else
          {
            fprintf(stderr, "Second GetTokenInformation failed\n");
          }

          free(privileges);
        }
        else
        {
          fprintf(stderr, "First GetTokenInformation failed\n");
        }
      }
      else
      {
        fprintf(stderr, "Impossible output from GetTokenInformation\n");
      }
    }
    else
    {
      fprintf(stderr, "LookupPrivilegeValue failed\n");
    }

    CloseHandle(hProcess);
  }
  else
  {
    fprintf(stderr, "OpenProcessToken failed\n");
  }

  LSA_HANDLE hPolicy;
  NTSTATUS r;
  LSA_OBJECT_ATTRIBUTES attributes = {0, NULL, NULL, 0, NULL, NULL};
  attributes.Length = sizeof(attributes);

  LUID seCreateSymbolicLinkPrivilege;

  if (LookupPrivilegeValue(NULL, SE_CREATE_SYMBOLIC_LINK_NAME, &seCreateSymbolicLinkPrivilege))
  {
    // POLICY_LOOKUP_NAMES: LsaLookupNames2, LsaEnumerateAccountRights, LsaLookupSids, LsaAddAccountRights
    // POLICY_VIEW_LOCAL_INFORMATION: LsaEnumerateAccountsWithUserRight
    // Elevation: LsaEnumerateAccountRights, LsaEnumerateAccountsWithUserRight, LsaRemoveAccountRights, LsaAddAccountRights
    if (NT_SUCCESS(r = LsaOpenPolicy(NULL, &attributes, POLICY_LOOKUP_NAMES | POLICY_VIEW_LOCAL_INFORMATION, &hPolicy)))
    {
      LSA_REFERENCED_DOMAIN_LIST* referencedDomains;
      LSA_TRANSLATED_SID2* sids;
      LSA_UNICODE_STRING name;
      name.Buffer = L"Users";
      name.Length = wcslen(name.Buffer) * sizeof(WCHAR);
      name.MaximumLength = name.Length + sizeof(WCHAR);
  
      if (NT_SUCCESS(r = LsaLookupNames2(hPolicy, LSA_LOOKUP_ISOLATED_AS_LOCAL, 1, &name, &referencedDomains, &sids)))
      {
        LSA_UNICODE_STRING* rights;
        ULONG count;
        LsaFreeMemory(referencedDomains);

        if (NT_SUCCESS(r = LsaEnumerateAccountRights(hPolicy, sids->Sid, &rights, &count)))
        {
          LSA_UNICODE_STRING* right = rights;
          printf("%ld right%s found\n", count, PLURAL(count));
          while (count-- > 0)
          {
            printf("  %.*S\n", right->Length / 2, right->Buffer);
            right++;
          }

          LsaFreeMemory(rights);

          LSA_ENUMERATION_INFORMATION* allSidsRaw;
          LSA_UNICODE_STRING lsaCreateSymbolicLinkPrivilege;
          lsaCreateSymbolicLinkPrivilege.Buffer = SE_CREATE_SYMBOLIC_LINK_NAME;
          lsaCreateSymbolicLinkPrivilege.Length = wcslen(lsaCreateSymbolicLinkPrivilege.Buffer) * sizeof(WCHAR);
          lsaCreateSymbolicLinkPrivilege.MaximumLength = lsaCreateSymbolicLinkPrivilege.Length + sizeof(WCHAR);
          if (NT_SUCCESS(r = LsaEnumerateAccountsWithUserRight(hPolicy, &lsaCreateSymbolicLinkPrivilege, (void**)&allSidsRaw, &count)))
          {
            LSA_ENUMERATION_INFORMATION* sid = allSidsRaw;
            PSID* allSids;
            PSID* p;
            PLSA_TRANSLATED_NAME names;
            ULONG i = count;

            printf("%ld SID%s found\n", count, PLURAL(count));
            p = allSids = (PSID*)malloc(count * sizeof(PSID));

            while (i-- > 0)
              *p++ = (sid++)->Sid;

            if (NT_SUCCESS(r = LsaLookupSids(hPolicy, count, allSids, &referencedDomains, &names)))
            {
              PLSA_TRANSLATED_NAME name = names;
              BOOL usersAssigned = FALSE;

              LsaFreeMemory(referencedDomains);

              while (count-- > 0)
              {
                LPTSTR sidString;
                USHORT len = name->Name.Length / 2;
                ConvertSidToStringSid(*allSids++, &sidString);
                printf("  %.*S (%S)\n", len, name->Name.Buffer, sidString);
                usersAssigned |= (len > 4 && !wcsncmp(L"Users", name->Name.Buffer, len));
                name++;
                LocalFree(sidString);
              }

              printf("Users had%s got SeCreateSymbolicLinkPrivilege\n", (usersAssigned ? "" : "n't"));
              if (usersAssigned)
              {
                if (!NT_SUCCESS(r = LsaRemoveAccountRights(hPolicy, sids->Sid, FALSE, &lsaCreateSymbolicLinkPrivilege, 1)))
                {
                  fprintf(stderr, "Lsa failed with code %x\n", r);
                }
              }
              else
              {
                if (!NT_SUCCESS(r = LsaAddAccountRights(hPolicy, sids->Sid, &lsaCreateSymbolicLinkPrivilege, 1)))
                {
                  fprintf(stderr, "LsaAddAccountRights failed with code %x\n", r);
                }
              }

              LsaFreeMemory(names);
            }
            else
            {
              fprintf(stderr, "LsaLookupSids2 failed with code %x\n", r);
            }
              
            LsaFreeMemory(allSidsRaw);
            free(allSids);
          }
          else
          {
            fprintf(stderr, "LsaEnumerateAccountsWithUserRight failed with code %x\n", r);
          }
        }
        else
        {
          fprintf(stderr, "LsaEnumerateAccountRights failed with code %x\n", r);
        }

        LsaFreeMemory(sids);
      }
      else
      {
        fprintf(stderr, "LsaLookupNames2 failed with code %x\n", r);
      }
  
      LsaClose(hPolicy);
    }
    else
    {
      fprintf(stderr, "LsaOpenPolicy failed with code %x\n", r);
    }
  }
  else
  {
    fprintf(stderr, "LookupPrivilegeValue failed\n");
  }
}
