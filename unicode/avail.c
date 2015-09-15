/*
 * Test program for determining available characters
 */

#include <stdio.h>

#include <windows.h>

int main(void)
{
  SetConsoleOutputCP(65001);

  printf("Surrogate: \U0001F42B\nTest characters: \u2298, \u2217, \u2197, \u2198, \u21bb\nSubs characters: \u00d8, \u2736, \u2191, \u2193, \u2195\n");

  printf("\xe2\x86\x91\n");

  HANDLE hConsoleOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  CONSOLE_FONT_INFOEX fontInfo;
  fontInfo.cbSize = sizeof(fontInfo);
  if (GetCurrentConsoleFontEx(hConsoleOutput, FALSE, &fontInfo))
  {
    printf("Current font is %S and is%s truetype\n", fontInfo.FaceName, (fontInfo.FontFamily & TMPF_TRUETYPE ? "" : "n't"));
  }
  else
  {
    printf("Error calling GetCurrentConsoleFontEx\n");
  }

  HDC hDC = GetDC(NULL);

  if (hDC)
  {
    HFONT hFont = CreateFontW(0, 0, 0, 0, FW_DONTCARE, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH, fontInfo.FaceName);

    if (hFont)
    {
      if (SelectObject(hDC, hFont))
      {
        LPWSTR testString = L"\u2298\u2217\u2197\u2198\u21bb\u00d8\u2736\u2191\u2193\u2195";
        int length = wcslen(testString);
        LPWORD indices = (LPWORD)malloc(length * sizeof(WORD));
        DWORD result = GetGlyphIndicesW(hDC, testString, length, indices, GGI_MARK_NONEXISTING_GLYPHS);
        if (result == length)
        {
          int i = 0;
          while (i++ < length)
          {
            if (*indices++ == 0xffff)
            {
              printf("Character %d is not available\n", i);
            }
          }
        }
        else
        {
          if (result == GDI_ERROR)
          {
            printf("Error calling GetGlyphIndicesW\n");
          }
          else
          {
            printf("Unexpected result of %d from GetGlyphIndicesW\n");
          }
        }

        free(indices);
      }
      else
      {
        printf("Error calling SelectObject\n");
      }

      if (!DeleteObject(hFont))
      {
        printf("Error calling DeleteObject\n");
      }
    }
    else
    {
      printf("Error calling CreateFontW\n");
    }

    if (ReleaseDC(NULL, hDC) != 1)
    {
      printf("Error calling ReleaseDC\n");
    }
  }
  else
  {
    printf("Error calling GetDC\n");
  }

  return 0;
}
