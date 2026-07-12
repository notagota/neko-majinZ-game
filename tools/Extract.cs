using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;

public static class Extract
{
	static int W, H;
	static int[] Px;
	static int Bg;

	static bool IsFg(int x, int y)
	{
		if (x < 0 || y < 0 || x >= W || y >= H) return false;
		int p = Px[y * W + x];
		int a = (p >> 24) & 0xFF;
		if (a < 16) return false;
		int dr = Math.Abs(((p >> 16) & 0xFF) - ((Bg >> 16) & 0xFF));
		int dg = Math.Abs(((p >> 8) & 0xFF) - ((Bg >> 8) & 0xFF));
		int db = Math.Abs((p & 0xFF) - (Bg & 0xFF));
		return (dr + dg + db) > 24;
	}

	static Rectangle Trim(Rectangle r, bool horiz, bool vert)
	{
		int x0 = r.Left, x1 = r.Right - 1, y0 = r.Top, y1 = r.Bottom - 1;
		if (horiz)
		{
			while (x0 <= x1 && !ColHasFg(x0, r.Top, r.Bottom)) x0++;
			while (x1 >= x0 && !ColHasFg(x1, r.Top, r.Bottom)) x1--;
		}
		if (vert)
		{
			while (y0 <= y1 && !RowHasFg(y0, x0, x1 + 1)) y0++;
			while (y1 >= y0 && !RowHasFg(y1, x0, x1 + 1)) y1--;
		}
		return Rectangle.FromLTRB(x0, y0, x1 + 1, y1 + 1);
	}
	static bool ColHasFg(int x, int y0, int y1) { for (int y = y0; y < y1; y++) if (IsFg(x, y)) return true; return false; }
	static bool RowHasFg(int y, int x0, int x1) { for (int x = x0; x < x1; x++) if (IsFg(x, y)) return true; return false; }

	static Bitmap Cut(Rectangle r, bool hueShift)
	{
		var bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppArgb);
		for (int y = 0; y < r.Height; y++)
			for (int x = 0; x < r.Width; x++)
			{
				if (!IsFg(r.X + x, r.Y + y)) continue;
				int p = Px[(r.Y + y) * W + (r.X + x)];
				bmp.SetPixel(x, y, hueShift ? Shift(p) : Color.FromArgb(p));
			}
		return bmp;
	}

	static Color Shift(int p)
	{
		var c = Color.FromArgb(p);
		float h = c.GetHue(), s = c.GetSaturation(), v = c.GetBrightness();
		if (h >= 170 && h <= 285 && s > 0.10f)
		{
			float nh = 50 + (h - 210) * 0.35f;
			if (nh < 28) nh = 28; if (nh > 85) nh = 85;
			return FromHsv(c.A, nh, Math.Min(1f, s * 1.05f), Math.Min(1f, v * 1.08f));
		}
		return c;
	}

	static Color FromHsv(int a, float h, float s, float l)
	{
		// GetHue/GetSaturation/GetBrightness are HSL, so convert back from HSL
		float c = (1 - Math.Abs(2 * l - 1)) * s;
		float x = c * (1 - Math.Abs((h / 60f) % 2 - 1));
		float m = l - c / 2;
		float r = 0, g = 0, b = 0;
		if (h < 60) { r = c; g = x; }
		else if (h < 120) { r = x; g = c; }
		else if (h < 180) { g = c; b = x; }
		else if (h < 240) { g = x; b = c; }
		else if (h < 300) { r = x; b = c; }
		else { r = c; b = x; }
		return Color.FromArgb(a, (int)((r + m) * 255), (int)((g + m) * 255), (int)((b + m) * 255));
	}

	static void SaveCanvas(Bitmap sprite, int cw, int ch, string path)
	{
		using (var canvas = new Bitmap(cw, ch, PixelFormat.Format32bppArgb))
		using (var g = Graphics.FromImage(canvas))
		{
			g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
			int ox = (cw - sprite.Width) / 2;
			int oy = ch - sprite.Height;
			g.DrawImageUnscaled(sprite, ox, oy);
			canvas.Save(path, ImageFormat.Png);
		}
	}

	public static void Run(string inputPath, string outRoot)
	{
		using (var src = new Bitmap(inputPath))
		{
			W = src.Width; H = src.Height;
			Px = new int[W * H];
			var d = src.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
			System.Runtime.InteropServices.Marshal.Copy(d.Scan0, Px, 0, Px.Length);
			src.UnlockBits(d);
		}
		Bg = Px[0];

		foreach (var sub in new[] { "z1", "z2", "fx", "ui" })
			Directory.CreateDirectory(Path.Combine(outRoot, sub));

		// character frames: name -> box (canvas 64x56, bottom-center)
		var chars = new Dictionary<string, Rectangle>
		{
			{"idle_0", new Rectangle(245,20,41,53)}, {"idle_1", new Rectangle(361,20,41,53)},
			{"walk_0", new Rectangle(295,23,55,48)}, {"walk_1", new Rectangle(408,23,55,48)},
			{"happy_0", new Rectangle(130,19,45,54)}, {"happy_1", new Rectangle(187,24,47,50)},
			{"taunt_0", new Rectangle(50,117,41,52)}, {"taunt_1", new Rectangle(104,117,41,52)},
			{"raise_0", new Rectangle(161,119,34,54)}, {"windup_0", new Rectangle(210,123,41,50)},
			{"punch_0", new Rectangle(263,122,52,50)}, {"punch2_0", new Rectangle(325,123,56,49)},
			{"blast_0", new Rectangle(393,122,49,50)},
			{"charge_0", new Rectangle(457,122,41,49)}, {"charge_1", new Rectangle(513,123,44,49)},
			{"hurt_0", new Rectangle(55,208,44,49)}, {"ball_0", new Rectangle(113,211,37,44)},
			{"fly_0", new Rectangle(164,209,61,45)}, {"jump_0", new Rectangle(234,199,49,52)},
			{"fall_0", new Rectangle(292,203,45,52)}, {"kick_0", new Rectangle(350,197,47,54)},
			{"rush_0", new Rectangle(407,203,45,52)},
			{"guard_0", new Rectangle(520,22,34,48)}, {"hurt2_0", new Rectangle(476,21,28,49)},
		};
		foreach (var kv in chars)
		{
			var r = Trim(kv.Value, true, true);
			using (var s1 = Cut(r, false)) SaveCanvas(s1, 64, 56, Path.Combine(outRoot, "z1", kv.Key + ".png"));
			using (var s2 = Cut(r, true)) SaveCanvas(s2, 64, 56, Path.Combine(outRoot, "z2", kv.Key + ".png"));
			Console.WriteLine("char " + kv.Key + " -> " + r);
		}

		// effects: trimmed, saved as-is
		var fx = new Dictionary<string, Rectangle>
		{
			{"aura", new Rectangle(27,10,90,88)},
			{"burst", new Rectangle(5,295,136,72)},
			{"lines", new Rectangle(5,368,135,62)},
			{"alert", new Rectangle(145,300,51,62)},
			{"spark_0", new Rectangle(229,299,36,32)},
			{"spark_1", new Rectangle(230,335,32,28)},
			{"beam_head", new Rectangle(267,296,68,68)},
			{"beam_tail", new Rectangle(436,296,26,68)},
		};
		foreach (var kv in fx)
		{
			var r = Trim(kv.Value, true, true);
			using (var s = Cut(r, false)) s.Save(Path.Combine(outRoot, "fx", kv.Key + ".png"), ImageFormat.Png);
			Console.WriteLine("fx " + kv.Key + " -> " + r);
		}
		// beam body: keep full horizontal slice for tiling, trim vertical only
		{
			var r = Trim(new Rectangle(336, 296, 100, 68), false, true);
			using (var s = Cut(r, false)) s.Save(Path.Combine(outRoot, "fx", "beam_body.png"), ImageFormat.Png);
			Console.WriteLine("fx beam_body -> " + r);
		}

		// portraits
		var p1r = Trim(new Rectangle(500, 248, 100, 44), true, true);
		using (var p1 = Cut(p1r, false))
		{
			p1.Save(Path.Combine(outRoot, "ui", "portrait1.png"), ImageFormat.Png);
			// icon 64x64: scale portrait to fit
			using (var icon = new Bitmap(64, 64, PixelFormat.Format32bppArgb))
			using (var g = Graphics.FromImage(icon))
			{
				g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
				float sc = Math.Min(64f / p1.Width, 64f / p1.Height);
				int nw = (int)(p1.Width * sc), nh = (int)(p1.Height * sc);
				g.DrawImage(p1, (64 - nw) / 2, (64 - nh) / 2, nw, nh);
				icon.Save(Path.Combine(outRoot, "icon.png"), ImageFormat.Png);
			}
		}
		Console.WriteLine("ui portrait1 -> " + p1r);
		using (var p2 = Cut(p1r, true)) p2.Save(Path.Combine(outRoot, "ui", "portrait2.png"), ImageFormat.Png);
		var pbr = Trim(new Rectangle(500, 296, 100, 134), true, true);
		using (var pb = Cut(pbr, false)) pb.Save(Path.Combine(outRoot, "ui", "portrait_big.png"), ImageFormat.Png);
		Console.WriteLine("ui portrait_big -> " + pbr);
		Console.WriteLine("DONE");
	}
}
