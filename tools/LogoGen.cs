using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

// Logo del titolo in stile Dragon Ball: "NEKO" viola e "MAJIN" rosa impilate
// con contorno nero spesso, e una grande "Z" rossa inclinata a destra.
// Disegnato a 2x e ridotto per bordi morbidi. Font Impact (fallback Arial).
// Uso (PowerShell):
//   Add-Type -Path tools\LogoGen.cs -ReferencedAssemblies System.Drawing
//   [LogoGen]::Run("assets\sprites\ui\logo.png")
public static class LogoGen
{
	static void DrawWord(Graphics g, FontFamily fam, string s, int size, Point p, Color top, Color bottom)
	{
		using (var path = new GraphicsPath())
		{
			path.AddString(s, fam, (int)FontStyle.Bold, size, p, StringFormat.GenericDefault);
			using (var outer = new Pen(Color.White, 22) { LineJoin = LineJoin.Round })
				g.DrawPath(outer, path);
			using (var pen = new Pen(Color.Black, 12) { LineJoin = LineJoin.Round })
				g.DrawPath(pen, path);
			var bounds = path.GetBounds();
			using (var br = new LinearGradientBrush(bounds, top, bottom, LinearGradientMode.Vertical))
				g.FillPath(br, path);
		}
	}

	public static void Run(string outPath)
	{
		int W = 840, H = 320;
		using (var big = new Bitmap(W, H, PixelFormat.Format32bppArgb))
		{
			using (var g = Graphics.FromImage(big))
			{
				g.SmoothingMode = SmoothingMode.AntiAlias;
				g.Clear(Color.Transparent);
				FontFamily fam;
				try { fam = new FontFamily("Impact"); }
				catch { fam = new FontFamily("Arial"); }
				// Z gigante rossa inclinata (alla DBZ), dietro alle parole
				using (var pz = new GraphicsPath())
				{
					pz.AddString("Z", fam, (int)FontStyle.Bold, 285, new Point(495, -12), StringFormat.GenericDefault);
					var m = new Matrix();
					m.RotateAt(-9f, new PointF(650, 160));
					pz.Transform(m);
					using (var outer = new Pen(Color.White, 26) { LineJoin = LineJoin.Round })
						g.DrawPath(outer, pz);
					using (var pen = new Pen(Color.Black, 15) { LineJoin = LineJoin.Round })
						g.DrawPath(pen, pz);
					var zb = pz.GetBounds();
					using (var br = new LinearGradientBrush(zb,
						Color.FromArgb(240, 60, 42), Color.FromArgb(148, 8, 14), LinearGradientMode.Vertical))
						g.FillPath(br, pz);
				}
				DrawWord(g, fam, "NEKO", 118, new Point(64, 16),
					Color.FromArgb(166, 84, 214), Color.FromArgb(96, 30, 138));
				DrawWord(g, fam, "MAJIN", 118, new Point(24, 158),
					Color.FromArgb(255, 128, 186), Color.FromArgb(216, 56, 126));
			}
			using (var small = new Bitmap(W / 2, H / 2, PixelFormat.Format32bppArgb))
			{
				using (var g2 = Graphics.FromImage(small))
				{
					g2.InterpolationMode = InterpolationMode.HighQualityBicubic;
					g2.DrawImage(big, 0, 0, W / 2, H / 2);
				}
				small.Save(outPath, ImageFormat.Png);
			}
		}
		Console.WriteLine("LOGO DONE");
	}
}
